import Foundation
import os

/// The app's own log lines: to the device log (subsystem `so.drafft.app`, readable in Console and a
/// sysdiagnose) and to Sentry, scrubbed on the way (`PrivacyGuard`). `info` and `notice` are
/// breadcrumbs (they come with the next error report), `error` is also a Sentry log line (searchable,
/// never an issue: the code that caught the error decides that, `Telemetry.unexpected`), `fault` is a
/// Sentry issue. Like Android's `TelemetryLogHandler` on `java.util.logging`.
///
/// Write lines without what people typed, their contact details or another person's id: the scrub
/// is a safety net, not a licence.
struct AppLog: Sendable {
    let category: String
    private let logger: Logger

    init(_ category: String) {
        self.category = category
        logger = Logger(subsystem: "so.drafft.app", category: category)
    }

    func debug(_ text: String) {
        logger.debug("\(text, privacy: .public)")
    }

    func info(_ text: String) {
        logger.info("\(text, privacy: .public)")
        Telemetry.breadcrumb("log", text, level: .info, data: ["logger": category])
    }

    func notice(_ text: String) {
        logger.notice("\(text, privacy: .public)")
        Telemetry.breadcrumb("log", text, level: .info, data: ["logger": category])
    }

    func error(_ text: String) {
        logger.error("\(text, privacy: .public)")
        Telemetry.breadcrumb("log", text, level: .warning, data: ["logger": category])
        Telemetry.log(.warning, text, attributes: ["logger": category])
    }

    /// Something that should never happen: a Sentry issue, grouped by its words.
    func fault(_ text: String) {
        logger.fault("\(text, privacy: .public)")
        Telemetry.log(.error, text, attributes: ["logger": category])
        Telemetry.problem(text, category, level: .error)
    }
}
