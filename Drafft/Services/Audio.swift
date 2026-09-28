import AVFoundation
import Observation

/// Hands an AVFoundation object built off the main thread back to it. Only ever touched by one
/// side at a time: built in the background, then used on the main actor.
private final class Handoff<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Every AVAudioSession call, in order on one serial queue, never on the main thread (activating can
/// block for a noticeable moment). The session is let go once playback or recording ends, with
/// `notifyOthersOnDeactivation`, so music from another app picks up again. The release waits a moment
/// and is dropped if anything asked for the session after it (the next clip, a recording): requests
/// are counted synchronously by the caller, so a release never lands after the activation that follows.
final class AudioSessionController: @unchecked Sendable {
    static let shared = AudioSessionController()

    private let queue = DispatchQueue(label: "so.drafft.audio-session", qos: .userInitiated)
    private let lock = NSLock()
    /// Bumped by every activation or release request; guarded by `lock`.
    private var generation = 0
    private var session: AVAudioSession { .sharedInstance() }

    private func bump() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        return generation
    }

    private var current: Int {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    /// Blocks the calling (background) thread until the session is active.
    func activate(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                  options: AVAudioSession.CategoryOptions = []) throws {
        _ = bump()
        try queue.sync {
            try setCategory(category, mode: mode, options: options)
            try session.setActive(true)
        }
    }

    /// Sets the category ahead of time, without activating (nothing else's audio is cut).
    func prepare(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                 options: AVAudioSession.CategoryOptions = []) {
        queue.async { try? self.setCategory(category, mode: mode, options: options) }
    }

    /// Playback or recording ended: the session goes back to other apps, unless something asks for
    /// it within the next moment.
    func release() {
        let mine = bump()
        queue.asyncAfter(deadline: .now() + 0.4) {
            guard self.current == mine else { return }
            try? self.session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                             options: AVAudioSession.CategoryOptions) throws {
        guard session.category != category || session.mode != mode || session.categoryOptions != options else { return }
        try session.setCategory(category, mode: mode, options: options)
    }
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
                    try AudioSessionController.shared.activate(.playback, mode: .spokenAudio)
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
                AudioSessionController.shared.release()
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
        // Something was playing or starting: the session goes back to other apps (dropped if a clip
        // starts right after, as `play` does).
        if currentURL != nil { AudioSessionController.shared.release() }
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
            AudioSessionController.shared.release()
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
        AudioSessionController.shared.prepare(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
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
                // Usually already set by prewarm(): only the activation is left to do here.
                try AudioSessionController.shared.activate(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
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
            AudioSessionController.shared.release()
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
        if recorder != nil { AudioSessionController.shared.release() }
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
    /// A voice intro saved on a profile: a picked file ("/…") or a URL on the server.
    nonisolated static func url(for voice: String) -> URL? {
        if voice.hasPrefix("/") { return URL(fileURLWithPath: voice) }
        if voice.hasPrefix("http") { return URL(string: voice) }
        return nil
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
        return await AudioDownloads.shared.fetch(remote, to: file)
    }
}

/// Clip downloads, streamed to disk (never held in memory), one per clip however many taps ask for it.
private actor AudioDownloads {
    static let shared = AudioDownloads()
    private var running: [URL: Task<URL?, Never>] = [:]

    func fetch(_ remote: URL, to file: URL) async -> URL? {
        if let task = running[file] { return await task.value }
        let task = Task<URL?, Never> {
            let link = await MediaURL.fresh(remote)
            guard let (temp, response) = try? await URLSession.shared.download(from: link) else { return nil }
            defer { try? FileManager.default.removeItem(at: temp) }
            let fm = FileManager.default
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  (try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil
            else { return nil }
            // Another download may have landed first: either copy is the same immutable clip.
            if fm.fileExists(atPath: file.path) { return file }
            return (try? fm.moveItem(at: temp, to: file)) != nil ? file : nil
        }
        running[file] = task
        let result = await task.value
        running[file] = nil
        return result
    }
}
