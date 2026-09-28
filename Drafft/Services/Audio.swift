import AVFoundation
import Observation

/// Hands an AVFoundation object built off the main thread back to it. Only ever touched by one
/// side at a time: built in the background, then used on the main actor.
private final class Handoff<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// One shared player: starting a clip stops whatever else was playing.
@MainActor
@Observable
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayback()

    private(set) var currentURL: URL?
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var elapsed: TimeInterval = 0
    var rate: Float = 1 {
        didSet { player?.rate = rate }
    }

    private var player: AVAudioPlayer?
    private var timer: Timer?
    /// The clip being loaded; a newer tap (or a stop) makes an older load land nowhere.
    private var loadToken = UUID()

    func isCurrent(_ url: URL?) -> Bool { url != nil && url == currentURL }

    /// Read straight from the player, for frame-by-frame progress (use inside a TimelineView).
    var liveProgress: Double {
        guard let player, player.duration > 0 else { return progress }
        return player.currentTime / player.duration
    }

    func toggle(_ url: URL) {
        if currentURL == url {
            if let player {
                if player.isPlaying { pause() } else { resume() }
            } else {
                stop() // still starting: a second tap cancels it
            }
            return
        }
        play(url)
    }

    /// The button flips to pause at once; the audio session and the player are set up off the
    /// main thread (activating the session can block for a noticeable moment, which froze
    /// touches right after tapping play).
    func play(_ url: URL) {
        stop()
        currentURL = url
        isPlaying = true
        let token = UUID()
        loadToken = token
        Task {
            // A clip on the server is played from its copy in Caches (nil when it couldn't be fetched).
            let file = url.isFileURL ? url : await AudioPlayback.localCopy(of: url)
            let made = await Task.detached(priority: .userInitiated) { () -> Handoff<AVAudioPlayer>? in
                do {
                    guard let file else { return nil }
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .spokenAudio)
                    try session.setActive(true)
                    let p = try AVAudioPlayer(contentsOf: file)
                    p.enableRate = true
                    p.prepareToPlay()
                    return Handoff(p)
                } catch {
                    return nil
                }
            }.value
            // Stopped, paused or switched to another clip meanwhile.
            guard loadToken == token, currentURL == url, isPlaying else { return }
            guard let p = made?.value else {
                currentURL = nil
                isPlaying = false
                return
            }
            p.delegate = self
            p.rate = rate
            p.play()
            player = p
            startTimer()
        }
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        player.currentTime = player.duration * fraction
        tick()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func resume() {
        player?.play()
        isPlaying = true
        startTimer()
    }

    func stop() {
        loadToken = UUID()
        player?.stop()
        player = nil
        timer?.invalidate()
        isPlaying = false
        progress = 0
        elapsed = 0
        currentURL = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let player, player.duration > 0 else { return }
        elapsed = player.currentTime
        progress = player.currentTime / player.duration
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.timer?.invalidate()
            self.isPlaying = false
            self.progress = 0
            self.elapsed = 0
            self.currentURL = nil
            self.player = nil
        }
    }
}

/// Microphone recorder that samples levels for a live waveform.
@MainActor
@Observable
final class VoiceRecorder {
    enum State: Equatable { case idle, recording, denied }

    private(set) var state: State = .idle
    private(set) var levels: [Float] = []
    private(set) var duration: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var url: URL?

    /// Shortest voice message kept: anything held less is a slip, discarded.
    static let minimumDuration: TimeInterval = 0.3

    /// Done when a chat opens, so a hold on the mic records sooner: the record category is set in
    /// advance (the session itself is only activated on the hold, so music playing isn't cut).
    static func prewarm() {
        guard !AudioPlayback.shared.isPlaying else { return }
        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        }
    }

    func start() async -> Bool {
        // Already allowed (the usual case): no round trip through the permission API.
        let granted = AVAudioApplication.shared.recordPermission == .granted
            ? true
            : await AVAudioApplication.requestRecordPermission()
        guard granted else {
            state = .denied
            return false
        }
        AudioPlayback.shared.stop()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        // Session and recorder are set up off the main thread: activating play-and-record can
        // block for a noticeable moment, and the hold on the mic must keep tracking the finger.
        let made = await Task.detached(priority: .userInitiated) { () -> Handoff<AVAudioRecorder>? in
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                // Voice only: 48 kb/s mono AAC is clear speech at ~6 KB a second, small enough to preload.
                AVEncoderBitRateKey: 48_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            do {
                let session = AVAudioSession.sharedInstance()
                // Usually already set by prewarm(): only the activation is left to do here.
                if session.category != .playAndRecord {
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                }
                try session.setActive(true)
                let r = try AVAudioRecorder(url: url, settings: settings)
                r.isMeteringEnabled = true
                r.record()
                return Handoff(r)
            } catch {
                return nil
            }
        }.value
        guard let r = made?.value else {
            state = .idle
            return false
        }
        recorder = r
        self.url = url
        levels = []
        duration = 0
        state = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        return true
    }

    private func sample() {
        guard let recorder else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let normalized = max(0.08, min(1, pow(10, db / 40)))
        levels.append(normalized)
        duration = recorder.currentTime
    }

    /// Stops and returns the recording, or nil when cancelled or too short.
    func finish(cancel: Bool = false) -> (url: URL, duration: TimeInterval, levels: [Float])? {
        timer?.invalidate()
        let d = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        state = .idle
        defer { levels = []; duration = 0 }
        guard !cancel, let url, d >= Self.minimumDuration else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        return (url, d, Self.downsample(levels, to: 40))
    }

    static func downsample(_ values: [Float], to count: Int) -> [Float] {
        guard values.count > count else {
            return values + Array(repeating: 0.12, count: max(0, count - values.count))
        }
        let step = Float(values.count) / Float(count)
        return (0..<count).map { i in
            let a = Int(Float(i) * step), b = min(values.count, Int(Float(i + 1) * step))
            let slice = values[a..<max(a + 1, b)]
            return slice.max() ?? 0.12
        }
    }
}

extension AudioPlayback {
    /// A voice intro saved on a profile: a picked file ("/…"), a URL on the server, or a demo clip.
    nonisolated static func url(for voice: String) -> URL? {
        if voice.hasPrefix("/") { return URL(fileURLWithPath: voice) }
        if voice.hasPrefix("http") { return URL(string: voice) }
        return MockData.audio(voice)
    }

    /// Where a clip on the server is kept: named after its key (the link's path), never its signature.
    nonisolated private static func cacheFile(for remote: URL) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("audio")
            .appendingPathComponent(remote.pathComponents.suffix(2).joined(separator: "-"))
    }

    /// AVAudioPlayer plays files only: a clip on the server is downloaded once into Caches (keys
    /// are immutable, so the copy never goes stale). A signed link that expired is renewed first;
    /// nil when the clip can't be fetched (offline, or no longer visible).
    static func localCopy(of remote: URL) async -> URL? {
        let file = cacheFile(for: remote)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let link = await MediaURL.fresh(remote)
        guard let (data, response) = try? await URLSession.shared.data(from: link),
              (response as? HTTPURLResponse)?.statusCode == 200,
              (try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil,
              (try? data.write(to: file, options: .atomic)) != nil else { return nil }
        return file
    }
}
