import Foundation
import Network

/// Whether the connection is limited, for how much the app fetches ahead and how big (`Images`,
/// `PhotoWindow`). Limited: cellular, Low Data Mode, or photos measured arriving slowly (under about
/// 1.6 Mbit/s each, back to normal above 3.2: a gap so one slow photo doesn't flip it back and forth).
/// The path comes from NWPathMonitor; the speed from the photos themselves (`measure`), an average that
/// follows the last few downloads.
final class NetworkQuality: @unchecked Sendable {
    static let shared = NetworkQuality()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var expensive = false
    private var constrained = false
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
            expensive = path.isExpensive
            constrained = path.isConstrained
            lock.unlock()
            changed()
        }
        monitor.start(queue: DispatchQueue(label: "so.drafft.network-quality", qos: .utility))
    }

    var isLimited: Bool {
        lock.lock(); defer { lock.unlock() }
        return limitedNow
    }

    /// Called now with the current state, then on every change (any thread).
    func onChange(_ observer: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        observers.append(observer)
        let now = limitedNow
        lock.unlock()
        observer(now)
    }

    /// Wraps a photo download's callbacks to time it. Only sizeable downloads count (a small file is all
    /// latency, which says nothing of the line).
    func measure(
        _ url: URL?,
        _ didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        _ completion: @escaping @Sendable (Error?) -> Void
    ) -> (@Sendable (Data, URLResponse) -> Void, @Sendable (Error?) -> Void) {
        guard let url, !url.isFileURL else { return (didReceiveData, completion) }
        let start = ContinuousClock.now
        let bytes = Counter()
        return ({ data, response in
            bytes.add(data.count)
            didReceiveData(data, response)
        }, { [weak self] error in
            let elapsed = ContinuousClock.now - start
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            if error == nil, bytes.value >= 60_000, seconds > 0 { self?.record(Double(bytes.value) / seconds) }
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
        let limited = expensive || constrained || slow
        let notify = limited != limitedNow ? observers : []
        limitedNow = limited
        lock.unlock()
        for observer in notify { observer(limited) }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var total = 0
        func add(_ n: Int) { lock.lock(); total += n; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return total }
    }
}
