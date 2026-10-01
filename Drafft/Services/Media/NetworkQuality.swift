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
    private var limitedNow = false
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

    /// Wraps a photo download's callbacks to time it: once, a second in (a slow line shows within the
    /// first download, finished or not), or at its end for one shorter than that and of some size (a small
    /// file is all latency, which says nothing of the line).
    func measure(
        _ url: URL?,
        _ didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        _ completion: @escaping @Sendable (Error?) -> Void
    ) -> (@Sendable (Data, URLResponse) -> Void, @Sendable (Error?) -> Void) {
        guard let url, !url.isFileURL else { return (didReceiveData, completion) }
        let start = ContinuousClock.now
        let bytes = Counter()
        let seconds: @Sendable () -> Double = {
            let elapsed = ContinuousClock.now - start
            return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        }
        return ({ [weak self] data, response in
            let total = bytes.add(data.count)
            let now = seconds()
            if now >= 1, bytes.claim() { self?.record(Double(total) / now) }
            didReceiveData(data, response)
        }, { [weak self] error in
            let now = seconds()
            let total = bytes.value
            if now >= 1 || (error == nil && total >= 60_000), now > 0, bytes.claim() { self?.record(Double(total) / now) }
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
        for observer in notify { observer(limited) }
    }

    /// A download's bytes so far, and whether its speed was recorded (once).
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var total = 0
        private var recorded = false
        func add(_ n: Int) -> Int { lock.lock(); defer { lock.unlock() }; total += n; return total }
        var value: Int { lock.lock(); defer { lock.unlock() }; return total }
        /// True the first time only.
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if recorded { return false }
            recorded = true
            return true
        }
    }
}
