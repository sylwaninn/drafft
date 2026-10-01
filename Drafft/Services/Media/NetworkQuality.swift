import Foundation
import Network

/// How the connection is doing, for what the app fetches first and how big (`Images`, `PhotoWindow`).
///
/// - `isSlow`: Low Data Mode, or photos measured arriving slowly (under about 1.6 Mbit/s each, back to
///   normal above 3.2: a gap so one slow photo doesn't flip it back and forth). Full copies are asked a
///   step lighter.
/// - `isLimited`: slow, or not measured yet on this network (at launch, after a switch from Wi-Fi to
///   cellular): small copies first and few downloads at once, so nothing starts with a dozen full photos
///   sharing a line nobody knows. On a fast line the first photo clears it in a fraction of a second.
///
/// The path comes from NWPathMonitor; the speed from the photos themselves (`measure`), an average that
/// follows the last few downloads.
final class NetworkQuality: @unchecked Sendable {
    static let shared = NetworkQuality()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var constrained = false
    private var interface: NWInterface.InterfaceType?
    /// Bytes per second, averaged over recent photo downloads.
    private var speed: Double?
    private var slow = false
    /// Unknown at launch: limited until measured.
    private var limitedNow = true
    /// Observers are told in order, one change after the other.
    private let notifications = DispatchQueue(label: "so.drafft.network-quality.notify")
    private var observers: [@Sendable (Bool) -> Void] = []

    private static let slowBelow = 200_000.0
    private static let fastAbove = 400_000.0

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            lock.lock()
            constrained = path.isConstrained
            // Another network: what was measured on the last one says nothing of this one.
            let now = path.availableInterfaces.first?.type
            if now != interface {
                interface = now
                speed = nil
                slow = false
            }
            lock.unlock()
            changed()
        }
        monitor.start(queue: DispatchQueue(label: "so.drafft.network-quality", qos: .utility))
    }

    var isLimited: Bool {
        lock.lock(); defer { lock.unlock() }
        return limitedNow
    }

    var isSlow: Bool {
        lock.lock(); defer { lock.unlock() }
        return constrained || slow
    }

    /// Called now with the current state, then on every change (any thread).
    func onChange(_ observer: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        observers.append(observer)
        let now = limitedNow
        lock.unlock()
        observer(now)
    }

    /// Wraps a photo download's callbacks to time it, from its first byte (renewing the link and the wait
    /// for the server aren't transfer time): once, a second after that byte (a slow line shows within the
    /// first download, finished or not), or at a successful end for a shorter one of some size. A failed or
    /// cancelled download says nothing of the line, nor do a few kilobytes.
    func measure(
        _ url: URL?,
        _ didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        _ completion: @escaping @Sendable (Error?) -> Void
    ) -> (@Sendable (Data, URLResponse) -> Void, @Sendable (Error?) -> Void) {
        guard let url, !url.isFileURL else { return (didReceiveData, completion) }
        let transfer = Counter()
        return ({ [weak self] data, response in
            let (total, seconds) = transfer.add(data.count)
            if seconds >= 1, total >= 32_000, transfer.claim() { self?.record(Double(total) / seconds) }
            didReceiveData(data, response)
        }, { [weak self] error in
            let (total, seconds) = transfer.now
            if error == nil, total >= 60_000, seconds > 0, transfer.claim() { self?.record(Double(total) / seconds) }
            completion(error)
        })
    }

    private func record(_ bytesPerSecond: Double) {
        lock.lock()
        let average = speed.map { $0 * 0.6 + bytesPerSecond * 0.4 } ?? bytesPerSecond
        speed = average
        if average < Self.slowBelow { slow = true } else if average > Self.fastAbove { slow = false }
        lock.unlock()
        changed()
    }

    private func changed() {
        lock.lock()
        let limited = constrained || slow || speed == nil
        let notify = limited != limitedNow ? observers : []
        limitedNow = limited
        lock.unlock()
        guard !notify.isEmpty else { return }
        notifications.async { for observer in notify { observer(limited) } }
    }

    /// A download's bytes since its first one, the time since then, and whether its speed was recorded (once).
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var total = 0
        private var first: ContinuousClock.Instant?
        private var recorded = false

        /// Adds a chunk: the bytes after the first chunk, and the seconds since it arrived.
        func add(_ n: Int) -> (Int, Double) {
            lock.lock(); defer { lock.unlock() }
            if first == nil { first = .now } else { total += n }
            return (total, elapsed)
        }

        var now: (Int, Double) { lock.lock(); defer { lock.unlock() }; return (total, elapsed) }

        private var elapsed: Double {
            guard let first else { return 0 }
            let d = ContinuousClock.now - first
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }

        /// True the first time only.
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if recorded { return false }
            recorded = true
            return true
        }
    }
}
