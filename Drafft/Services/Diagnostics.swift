import Foundation
import MetricKit

/// What the system measures of the app on people's iPhones (MetricKit): launch time, hangs, memory,
/// and crash or hang diagnostics. Apple sends the day's payloads about once a day, and diagnostics
/// right away (iOS 15 and later).
///
/// They're written to the device log (subsystem `so.drafft.app`, category `metrics`) and kept as JSON
/// files in Application Support/Diagnostics (the last 30), readable from Xcode's Devices window or a
/// sysdiagnose. The daily summary is also a Sentry log line, searchable by release. Sentry receives
/// the crash and hang diagnostics on its own (its MetricKit integration), so here they're a log line
/// too, never a second issue.
final class Diagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = Diagnostics()

    private static let log = AppLog("metrics")
    private static let kept = 30

    /// Once, at launch.
    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let summary = Self.summary(payload)
            Self.log.info(summary)
            Telemetry.log(.info, summary, attributes: ["logger": "metrics"])
            Self.keep(payload.jsonRepresentation(), kind: "metrics")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let hangs = payload.hangDiagnostics?.count ?? 0, crashes = payload.crashDiagnostics?.count ?? 0
            Self.log.error("diagnostics: \(crashes) crash(es), \(hangs) hang(s)")
            Self.keep(payload.jsonRepresentation(), kind: "diagnostics")
        }
    }

    /// The numbers worth reading at a glance: time to first draw, launches and resumes, hang time,
    /// peak memory.
    private static func summary(_ p: MXMetricPayload) -> String {
        var parts = ["metrics \(p.timeStampBegin.formatted(.iso8601)) to \(p.timeStampEnd.formatted(.iso8601))"]
        if let launch = p.applicationLaunchMetrics {
            parts.append("first draw \(median(launch.histogrammedTimeToFirstDraw)) ms")
            parts.append("resume \(median(launch.histogrammedApplicationResumeTime)) ms")
        }
        if let hangs = p.applicationResponsivenessMetrics {
            parts.append("hang \(median(hangs.histogrammedApplicationHangTime)) ms")
        }
        if let memory = p.memoryMetrics {
            parts.append("peak memory \(Int(memory.peakMemoryUsage.converted(to: .megabytes).value)) MB")
        }
        return parts.joined(separator: ", ")
    }

    /// The histogram's middle bucket start, in milliseconds (an estimate: MetricKit only gives buckets).
    private static func median(_ histogram: MXHistogram<UnitDuration>) -> Int {
        var buckets: [(start: Double, count: Int)] = []
        let items = histogram.bucketEnumerator
        while let bucket = items.nextObject() as? MXHistogramBucket<UnitDuration> {
            buckets.append((bucket.bucketStart.converted(to: .milliseconds).value, bucket.bucketCount))
        }
        let total = buckets.reduce(0) { $0 + $1.count }
        var seen = 0
        for bucket in buckets {
            seen += bucket.count
            if seen * 2 >= total { return Int(bucket.start) }
        }
        return 0
    }

    private static func keep(_ json: Data, kind: String) {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(Int(Date.now.timeIntervalSince1970))-\(kind).json")
        try? json.write(to: file, options: .atomic)
        // Named by time: the oldest go first.
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for old in files.dropLast(kept) { try? FileManager.default.removeItem(at: old) }
    }
}
