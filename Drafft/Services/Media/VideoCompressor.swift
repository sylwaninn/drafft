@preconcurrency import AVFoundation
import VideoToolbox

/// A video ready to upload: an MP4 file on disk, plus its poster frame (a prepared photo).
struct PreparedVideo: Sendable {
    let fileURL: URL
    let byteSize: Int
    let width: Int
    let height: Int
    let duration: Double
    let poster: PreparedPhoto

    var contentType: String { "video/mp4" }
}

/// Videos are transcoded on the phone before upload, so they can be preloaded whole and start instantly.
///
/// - HEVC, 720p (long edge 1280), ~1.6 Mb/s: ~3 MB for 15 s, ~6 MB for 30 s, instead of 30–100 MB. Every iPhone
///   that runs iOS 26 decodes HEVC in hardware.
/// - Progressive MP4 with the index at the front (`shouldOptimizeForNetworkUse`): playback starts on the
///   first bytes, no HLS manifest round trip.
/// - HDR (iPhone Dolby Vision / HLG) is tone-mapped to SDR BT.709 by the video composition, so it doesn't
///   look washed out on SDR screens and in the poster.
/// - Rotation is baked into the pixels by the composition.
enum VideoCompressor {
    struct Settings: Sendable {
        var maxLongEdge: Double = 1280
        var videoBitRate = 1_600_000
        var audioBitRate = 96_000
        /// Longer sources are cut to this length (profile videos: 30 s, enforced by the backend too).
        var maxDuration: Double?

        static let profile = Settings(maxDuration: 30)
        static let chat = Settings(maxDuration: 180)
    }

    static func prepare(_ source: URL, settings: Settings) async throws -> PreparedVideo {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        else { throw MediaPreparationError.noVideoTrack }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let assetDuration = try await asset.load(.duration)
        let frameRate = try await videoTrack.load(.nominalFrameRate)

        let limit = settings.maxDuration.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? assetDuration
        let timeRange = CMTimeRange(start: .zero, duration: CMTimeMinimum(assetDuration, limit))

        // Upright frames at the source size, converted to SDR BT.709.
        var configuration = try await AVVideoComposition.Configuration(for: asset)
        configuration.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        configuration.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        configuration.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let composition = AVVideoComposition(configuration: configuration)
        let upright = configuration.renderSize
        let scale = min(1, settings.maxLongEdge / max(upright.width, upright.height))
        let width = even(upright.width * scale)
        let height = even(upright.height * scale)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("video-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.videoBitRate,
                AVVideoExpectedSourceFrameRateKey: frameRate > 0 ? frameRate : 30,
                // A keyframe every 2 s keeps seeking and the first frame cheap.
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String
            ]
        ])
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)

        var audio: (AVAssetReaderTrackOutput, AVAssetWriterInput)?
        if let audioTrack {
            let pcm: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2]
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: pcm)
            audioOutput.alwaysCopiesSampleData = false
            reader.add(audioOutput)
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: settings.audioBitRate
            ])
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
            audio = (audioOutput, audioInput)
        }

        guard reader.startReading(), writer.startWriting() else {
            throw MediaPreparationError.exportFailed(String(describing: reader.error ?? writer.error))
        }
        writer.startSession(atSourceTime: timeRange.start)

        let transcode = Transcode(reader: reader, writer: writer, pairs: [(videoOutput, videoInput)] + (audio.map { [$0] } ?? []))
        do {
            try await transcode.run()
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: settings.maxLongEdge, height: settings.maxLongEdge)
        let poster = try PhotoCompressor.prepare(try await generator.image(at: .zero).image)

        let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
        return PreparedVideo(fileURL: output, byteSize: size, width: width, height: height,
                             duration: timeRange.duration.seconds, poster: poster)
    }

    private static func even(_ value: Double) -> Int { max(2, Int(value.rounded()) & ~1) }
}

/// Pumps samples from the reader into the writer, one serial queue per track.
/// AVFoundation objects aren't Sendable; they're only touched from these queues, then from `finish`.
private final class Transcode: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let pairs: [(AVAssetReaderOutput, AVAssetWriterInput)]

    init(reader: AVAssetReader, writer: AVAssetWriter, pairs: [(AVAssetReaderOutput, AVAssetWriterInput)]) {
        self.reader = reader
        self.writer = writer
        self.pairs = pairs
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()
            for (index, (output, input)) in pairs.enumerated() {
                group.enter()
                let queue = DispatchQueue(label: "so.drafft.transcode.\(index)")
                input.requestMediaDataWhenReady(on: queue) {
                    while input.isReadyForMoreMediaData {
                        guard let sample = output.copyNextSampleBuffer() else {
                            input.markAsFinished()
                            group.leave()
                            return
                        }
                        if !input.append(sample) {
                            self.reader.cancelReading()
                            input.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            }
            group.notify(queue: .global(qos: .userInitiated)) {
                if self.reader.status == .failed || self.writer.status == .failed {
                    self.writer.cancelWriting()
                    let error = self.writer.error ?? self.reader.error
                    continuation.resume(throwing: MediaPreparationError.exportFailed(String(describing: error)))
                    return
                }
                self.writer.finishWriting {
                    if self.writer.status == .completed {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: MediaPreparationError.exportFailed(String(describing: self.writer.error)))
                    }
                }
            }
        }
    }
}
