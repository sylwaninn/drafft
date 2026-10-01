import Foundation
import Nuke
import os
import UIKit

#if DECK_PHOTO_METRICS

/// Deck photo timings, for measuring on a device: compiled only into a build made with
/// `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DECK_PHOTO_METRICS'`, never into a shipped one.
/// For each deck portrait: where it came from (memory, disk, network) and how long it took, split into
/// time waiting in Nuke's queue, download and decode; whether the card in play had its photo when it came
/// on top. Written to the system log and to Documents/deck-photos.log
/// (`xcrun devicectl device copy from --domain-type appDataContainer --source Documents/deck-photos.log`).
/// Launched with `-deckPhotoReset`, the app starts from an empty photo cache (`Images.configure`).
@MainActor
enum DeckPhotoMetrics {
    private static let log = Logger(subsystem: "so.drafft.app", category: "deck-photos")
    private static let clock = ContinuousClock()
    private static let file = URL.documentsDirectory.appending(path: "deck-photos.log")
    /// Everything below is keyed by the object (`MediaURL.key`), whatever the link or width.
    private static var tracked: Set<String> = []
    private static var started: [String: ContinuousClock.Instant] = [:]
    private static var network: [String: (start: ContinuousClock.Instant, end: ContinuousClock.Instant, bytes: Int, status: Int)] = [:]
    private static var ready: [String: String] = [:]
    private static var top: (key: String, since: ContinuousClock.Instant)?
    private static var lastTop: ContinuousClock.Instant?
    private static var swipes = 0

    static func track(_ names: [String]) {
        if tracked.isEmpty {
            let reset = ProcessInfo.processInfo.arguments.contains("-deckPhotoReset") ? " (caches emptied)" : ""
            say("session \(UIDevice.current.model) \(UIDevice.current.systemVersion)\(reset)")
        }
        tracked.formUnion(names.map(key))
    }

    static func appeared(_ name: String) {
        // Every photo: a card can appear before the deck says it's tracked.
        let k = key(name)
        guard started[k] == nil, ready[k] == nil else { return }
        started[k] = clock.now
    }

    static func finished(_ name: String, _ result: Result<ImageResponse, Error>) {
        let k = key(name)
        let now = clock.now
        let begin = started.removeValue(forKey: k)
        let net = network.removeValue(forKey: k)
        guard tracked.contains(k) else { return }
        let id = short(k)
        switch result {
        case .success(let response):
            let source = switch response.cacheType {
            case .memory: "memory"
            case .disk: "disk"
            case nil: "network"
            }
            let image = response.image
            let px = "\(Int(image.size.width * image.scale))x\(Int(image.size.height * image.scale))"
            let width = response.request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "w" }?.value } ?? "original"
            var line = "load \(id) \(source) total=\(begin.map { "\(ms(now - $0))" } ?? "?") ms"
            if let net {
                let queued = begin.map { ms(net.start - $0) }.map(String.init) ?? "?"
                line += " queue=\(queued) download=\(ms(net.end - net.start)) decode=\(ms(now - net.end))"
                line += " \(net.bytes / 1024) kB http=\(net.status)"
            }
            line += " w=\(width) \(px) pending=\(pending)"
            let wasReady = ready[k] != nil
            ready[k] = source
            say(line)
            if !wasReady, let top, top.key == k {
                say("top \(id) WAITED \(ms(now - top.since)) ms (\(source))")
            }
        case .failure(let error):
            say("load \(id) FAILED \(String(describing: error))")
        }
    }

    static func becameTop(_ name: String?) {
        guard let name else { return }
        let k = key(name)
        tracked.insert(k)
        let now = clock.now
        let pace = lastTop.map { "\(ms(now - $0)) ms after previous" } ?? "first"
        lastTop = now
        swipes += 1
        top = (k, now)
        if let source = ready[k] {
            say("top #\(swipes) \(short(k)) ready (\(source)) \(pace)")
        } else {
            say("top #\(swipes) \(short(k)) NOT READY \(pace) pending=\(pending)")
        }
    }

    /// Wraps a download's callbacks (any thread) to record when it left the queue, its bytes and its end.
    nonisolated static func observe(
        _ url: URL?,
        _ didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        _ completion: @escaping @Sendable (Error?) -> Void
    ) -> (@Sendable (Data, URLResponse) -> Void, @Sendable (Error?) -> Void) {
        guard let url, !url.isFileURL else { return (didReceiveData, completion) }
        let start = ContinuousClock.now
        let counter = Counter()
        return ({ data, response in
            counter.add(data.count, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
            didReceiveData(data, response)
        }, { error in
            let end = ContinuousClock.now
            let (bytes, status) = counter.value
            Task { @MainActor in
                network[key(url.absoluteString)] = (start, end, bytes, status)
            }
            completion(error)
        })
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = 0
        private var status = 0
        func add(_ n: Int, status: Int) { lock.lock(); bytes += n; self.status = status; lock.unlock() }
        var value: (Int, Int) { lock.lock(); defer { lock.unlock() }; return (bytes, status) }
    }

    /// Deck portraits started and not shown yet.
    private static var pending: Int { started.keys.filter(tracked.contains).count }

    /// To the system log and to Documents/deck-photos.log.
    private static func say(_ line: String) {
        log.notice("\(line, privacy: .public)")
        let stamp = Date().formatted(.iso8601.time(includingFractionalSeconds: true))
        let data = Data("\(stamp) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }

    nonisolated private static func key(_ name: String) -> String {
        URL(string: name).flatMap(MediaURL.key(of:)) ?? name
    }

    private static func ms(_ d: Duration) -> Int {
        Int(d.components.seconds * 1_000) + Int(d.components.attoseconds / 1_000_000_000_000_000)
    }

    private static func short(_ key: String) -> String {
        let parts = key.split(separator: "/")
        let user = parts.count > 1 ? String(parts[1].prefix(4)) : "?"
        return "\(user)/\(parts.last.map { String($0.prefix(12)) } ?? "?")"
    }
}
#endif
