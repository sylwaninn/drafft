import Foundation
@preconcurrency import Sentry

/// `Telemetry.CrashReporter` on Sentry (EU region, picked by the DSN). Crashes, app hangs, watchdog
/// terminations, MetricKit's hang, CPU and disk diagnostics, the errors `Telemetry.unexpected` reports,
/// app start, slow and frozen frames, request traces, the app's logs. What it never takes: screenshots,
/// the view hierarchy, session replays (they would show people's photos and messages), the IP address,
/// the user's name or email.
struct SentryCrashReporter: Telemetry.CrashReporter {
    func setUser(_ id: String?) {
        SentrySDK.setUser(id.map { User(userId: $0) })
    }

    func setTag(_ key: String, _ value: String?) {
        SentrySDK.configureScope { scope in
            if let value { scope.setTag(value: value, key: key) } else { scope.removeTag(key: key) }
        }
    }

    func breadcrumb(_ crumb: Telemetry.Breadcrumb) {
        let breadcrumb = Breadcrumb(level: crumb.level.sentry, category: crumb.category)
        breadcrumb.message = crumb.message
        breadcrumb.type = switch crumb.category {
        case "navigation": "navigation"
        case "http": "http"
        case "error": "error"
        case "product", "ui": "user"
        default: "default"
        }
        if !crumb.data.isEmpty { breadcrumb.data = crumb.data.mapValues(\.raw) }
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    func capture(_ error: Error, _ report: Telemetry.ErrorReport) {
        SentrySDK.capture(error: error) { scope in Self.apply(report, to: scope) }
    }

    func message(_ text: String, _ level: Telemetry.Level, _ report: Telemetry.ErrorReport) {
        SentrySDK.capture(message: text) { scope in
            scope.setLevel(level.sentry)
            Self.apply(report, to: scope)
        }
    }

    func log(_ level: Telemetry.Level, _ text: String, _ attributes: [String: TelemetryValue]) {
        let attributes = attributes.mapValues(\.raw)
        let logger = SentrySDK.logger
        switch level {
        case .debug: logger.debug(text, attributes: attributes)
        case .info: logger.info(text, attributes: attributes)
        case .warning: logger.warn(text, attributes: attributes)
        case .error: logger.error(text, attributes: attributes)
        case .fatal: logger.fatal(text, attributes: attributes)
        }
    }

    func startSpan(_ operation: String, _ description: String) -> any Telemetry.Span {
        // Inside a running trace (app start, a flow): a child. Otherwise a trace of its own, so every
        // request shows in Performance with its own latency (sampled by `tracesSampler`).
        let span = SentrySDK.span?.startChild(operation: operation, description: description)
            ?? SentrySDK.startTransaction(name: description, operation: operation, bindToScope: false)
        return SpanBox(span: span)
    }

    /// Sentry's span, finished once.
    private final class SpanBox: Telemetry.Span, @unchecked Sendable {
        let span: Sentry.Span
        init(span: Sentry.Span) { self.span = span }

        func setData(_ key: String, _ value: TelemetryValue) { span.setData(value: value.raw, key: key) }

        func finish(ok: Bool) {
            guard !span.isFinished else { return }
            span.finish(status: ok ? .ok : .internalError)
        }
    }

    private static func apply(_ report: Telemetry.ErrorReport, to scope: Scope) {
        scope.setTag(value: report.area, key: "area")
        if let action = report.action { scope.setTag(value: action, key: "action") }
        for (key, value) in report.extra { scope.setExtra(value: value.description, key: key) }
        if let fingerprint = report.fingerprint { scope.setFingerprint(fingerprint) }
    }

    // MARK: Start

    /// Starts Sentry, first thing at launch, so a crash during launch is caught. Nil without a DSN (or
    /// with one outside the EU region): Sentry stays off.
    static func start(_ config: TelemetryConfig) -> SentryCrashReporter? {
        guard config.hasSentry else { return nil }
        SentrySDK.start { options in
            options.dsn = config.sentryDSN
            options.environment = config.environment
            options.releaseName = config.release
            options.dist = config.build
            options.debug = false

            // Privacy: nothing that shows people, their messages or where they are. Default PII (IP
            // address, user details) stays off, Sentry's default; `scrubbed` makes sure.
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.sessionReplay.sessionSampleRate = 0
            options.sessionReplay.onErrorSampleRate = 0
            options.reportAccessibilityIdentifier = false
            options.enableUserInteractionTracing = false
            // Requests: the app traces its own backend calls (`Backend`, without their query). Sentry's
            // automatic ones would also record Stream, RevenueCat and storage URLs (signed links), and
            // turn every 5xx into an issue the app already classifies (`Telemetry.unexpected`).
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.tracePropagationTargets = []
            // File paths carry the account's id (its cache), and SwiftUI screens aren't view controllers
            // worth timing: the app names its screens (`ScreenTracker`).
            options.enableFileIOTracing = false
            options.enableCoreDataTracing = false
            options.enableUIViewControllerTracing = false

            // Crashes, hangs, release health. MetricKit's diagnostics (hangs, CPU and disk use) arrive
            // the next day with the scope of then; `Diagnostics` keeps the daily metrics on the phone.
            options.enableCrashHandler = true
            options.enableAppHangTracking = true
            options.enableWatchdogTerminationTracking = true
            options.enableAutoSessionTracking = true
            options.enableMetricKit = true
            options.maxBreadcrumbs = 150

            // Performance: app start (its own transaction, there are no view controllers to hang it on),
            // slow and frozen frames, request traces, some profiles. A request outside any trace is a
            // trace of its own: the most frequent kind, so the most sampled down (the quota goes to app
            // starts and uploads, where slowness is felt).
            options.enableAutoPerformanceTracing = true
            options.experimental.enableStandaloneAppStartTracing = true
            options.tracesSampler = { context in
                NSNumber(value: context.transactionContext.operation == "http.client"
                    ? config.requestSampleRate : config.tracesSampleRate)
            }
            // Profiles follow the sampled traces (the default, manual, would never start one).
            if config.profileSampleRate > 0 {
                options.configureProfiling = { profiling in
                    profiling.sessionSampleRate = Float(config.profileSampleRate)
                    profiling.lifecycle = .trace
                }
            }

            // The app's logs (`AppLog`, `Telemetry.log`).
            options.enableLogs = true

            options.beforeSend = { event in scrubbed(event) }
            options.beforeBreadcrumb = { crumb in
                crumb.message = crumb.message.map(PrivacyGuard.scrub)
                if let url = crumb.data?["url"] as? String { crumb.data?["url"] = PrivacyGuard.path(url) }
                return crumb
            }
            options.beforeSendLog = { log in
                log.body = PrivacyGuard.scrub(log.body)
                return log
            }
            options.initialScope = { scope in
                scope.setTag(value: config.environment, key: "flavor")
                return scope
            }
        }
        return SentryCrashReporter()
    }

    /// The last pass over an event: what an error's message may carry, and the user's id only.
    private static func scrubbed(_ event: Event) -> Event {
        if let message = event.message {
            let clean = SentryMessage(formatted: PrivacyGuard.scrub(message.formatted))
            clean.message = message.message.map(PrivacyGuard.scrub)
            event.message = clean
        }
        for exception in event.exceptions ?? [] { exception.value = exception.value.map(PrivacyGuard.scrub) }
        for crumb in event.breadcrumbs ?? [] { crumb.message = crumb.message.map(PrivacyGuard.scrub) }
        if let user = event.user {
            user.email = nil
            user.username = nil
            user.name = nil
            user.ipAddress = nil
            user.geo = nil
        }
        event.request = nil
        return event
    }
}

private extension Telemetry.Level {
    var sentry: SentryLevel {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warning: .warning
        case .error: .error
        case .fatal: .fatal
        }
    }
}
