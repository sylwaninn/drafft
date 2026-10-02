import Foundation
import Synchronization

/// What leaves the phone about how the app behaves, callable from anywhere (models, services, views),
/// from any thread. Two services, each with its job (docs/telemetry.md):
///
/// - **Sentry** (`CrashReporter`): crashes, hangs, unexpected errors, slow requests, the app's own logs.
///   For the service's reliability and security (legitimate interest, named in the privacy policy):
///   always on in a build that has a DSN, tied to the account's id, never to a name, an email or a number.
/// - **PostHog** (`Analytics`): how the app is used, as the events of `AnalyticsEvent`, nothing typed by
///   people. Linked to the account only with the person's consent (`AnalyticsConsent`); without it the
///   events stay anonymous (a random id of this install), and a refusal sends nothing at all.
///
/// Both engines are installed at launch (`TelemetrySession.start`). Until then, in unit tests and in a build
/// without keys, every call does nothing. `PrivacyGuard` checks everything sent. The Android app has the
/// same object, events and rules (`so.drafft.core.data.telemetry`).
enum Telemetry {
    /// Sentry's side.
    protocol CrashReporter: Sendable {
        /// The account's id (the Supabase user id), or nil signed out.
        func setUser(_ id: String?)
        func setTag(_ key: String, _ value: String?)
        func breadcrumb(_ crumb: Breadcrumb)
        func capture(_ error: Error, _ report: ErrorReport)
        func message(_ text: String, _ level: Level, _ report: ErrorReport)
        /// A structured log line (Sentry Logs), searchable with the events of the same session.
        func log(_ level: Level, _ text: String, _ attributes: [String: TelemetryValue])
        /// A timed operation (a request, an upload): a child of the running trace, or a trace of its own.
        func startSpan(_ operation: String, _ description: String) -> any Span
    }

    /// PostHog's side.
    protocol Analytics: Sendable {
        func capture(_ name: String, _ properties: [String: TelemetryValue])
        func screen(_ name: String, _ properties: [String: TelemetryValue])
        /// Links this install's events to the account (only with `AnalyticsConsent.granted`).
        func identify(_ id: String)
        func setPersonProperties(_ properties: [String: TelemetryValue])
        /// A property sent with every event from now on ("super property").
        func register(_ key: String, _ value: TelemetryValue)
        /// A new anonymous id: what follows can't be tied to what came before (sign-out, deletion).
        func reset()
        /// Whether anything is sent: off while the person refused.
        func setEnabled(_ enabled: Bool)
        func flush()
    }

    protocol Span: Sendable {
        func setData(_ key: String, _ value: TelemetryValue)
        func finish(ok: Bool)
    }

    enum Level: String, Sendable { case debug, info, warning, error, fatal }

    /// A step that comes with the next error report (Sentry's breadcrumb).
    struct Breadcrumb: Sendable, Equatable {
        /// "navigation", "http", "ui", "product", "auth", "log"...
        var category: String
        var message: String
        var level: Level = .info
        var data: [String: TelemetryValue] = [:]
    }

    /// Where an error happened, to group and search them.
    struct ErrorReport: Sendable, Equatable {
        /// The feature: "discover", "chat", "purchase"... (Sentry tag `area`).
        var area: String
        /// What it was doing: "swipe", "load_deck"... (Sentry tag `action`).
        var action: String?
        var extra: [String: TelemetryValue] = [:]
        /// Groups events that are the same problem whatever the message says.
        var fingerprint: [String]?
    }

    // MARK: State

    private struct State {
        var crashes: any CrashReporter = NoCrashes()
        var analytics: any Analytics = NoAnalytics()
        var classifier: any ErrorClassifier = BasicErrorClassifier()
        var consent: AnalyticsConsent = .unknown
        /// The signed-in account, kept to identify again when the consent changes.
        var userID: String?
        var identified = false
        /// The super properties, sent again after a reset (PostHog's reset forgets them).
        var registered: [String: TelemetryValue] = [:]
        /// The screen on show, for the next error report and the events' `screen` property.
        var screen: Screen?
    }

    private static let state = Mutex(State())

    private static var crashes: any CrashReporter { state.withLock { $0.crashes } }
    private static var analytics: any Analytics { state.withLock { $0.analytics } }

    /// Installs the engines (launch, or a unit test's fakes). Nil leaves that side as it is.
    static func install(crashes: (any CrashReporter)? = nil, analytics: (any Analytics)? = nil,
                        classifier: (any ErrorClassifier)? = nil) {
        state.withLock { s in
            if let crashes { s.crashes = crashes }
            if let analytics { s.analytics = analytics }
            if let classifier { s.classifier = classifier }
        }
    }

    /// Back to nothing installed (unit tests).
    static func uninstall() {
        state.withLock { $0 = State() }
    }

    /// What the person said about usage analytics (applied by `applyConsent`).
    static var consent: AnalyticsConsent { state.withLock { $0.consent } }

    static var currentScreen: Screen? { state.withLock { $0.screen } }

    // MARK: Product analytics

    /// A product event: to PostHog (if allowed), and as a breadcrumb for the next error report.
    static func track(_ event: AnalyticsEvent) {
        let properties = PrivacyGuard.properties(event.name, event.properties)
        let (crashes, analytics, consent, screen) = state.withLock { ($0.crashes, $0.analytics, $0.consent, $0.screen) }
        crashes.breadcrumb(Breadcrumb(category: "product", message: event.name, data: properties))
        guard consent != .denied else { return }
        var withScreen = properties
        if let screen { withScreen["screen"] = .string(screen.id) }
        analytics.capture(event.name, withScreen)
    }

    /// A screen shown. Repeats of the one on show are ignored (a view built again, a tab tapped again).
    static func screen(_ screen: Screen, _ properties: TelemetryProperties = [:]) {
        let changed: (from: Screen?, crashes: any CrashReporter, analytics: any Analytics, consent: AnalyticsConsent)? =
            state.withLock { s in
                guard s.screen != screen else { return nil }
                let from = s.screen
                s.screen = screen
                return (from, s.crashes, s.analytics, s.consent)
            }
        guard let changed else { return }
        changed.crashes.setTag("screen", screen.id)
        changed.crashes.breadcrumb(Breadcrumb(category: "navigation", message: screen.id,
                                              data: changed.from.map { ["from": .string($0.id)] } ?? [:]))
        guard changed.consent != .denied else { return }
        changed.analytics.screen(screen.id, PrivacyGuard.properties(screen.id, properties))
    }

    // MARK: Identity

    /// The signed-in account (nil signed out). Sentry always gets the id; PostHog only with the
    /// person's consent. Signing out (or into another account) starts a new anonymous id.
    static func signedIn(_ id: String?) {
        let (crashes, reset) = state.withLock { s in
            let previous = s.userID
            s.userID = id
            let reset = previous != nil && previous != id
            if reset { s.identified = false }
            return (s.crashes, reset)
        }
        crashes.setUser(id)
        if reset { resetAnalytics() }
        identifyIfAllowed()
    }

    /// Facts about the account for analytics (person properties), only while identified.
    static func describeAccount(_ properties: TelemetryProperties) {
        let safe = PrivacyGuard.properties("person", properties)
        let (crashes, analytics, identified) = state.withLock { ($0.crashes, $0.analytics, $0.identified) }
        for (key, value) in safe { crashes.setTag(key, value.description) }
        if identified { analytics.setPersonProperties(safe) }
    }

    /// Sent with every event and error report (the app's language, the build's environment...).
    static func register(_ key: String, _ value: any TelemetryValueConvertible) {
        let safe = PrivacyGuard.properties("register", [key: value])
        let (crashes, analytics) = state.withLock { s in
            for (k, v) in safe { s.registered[k] = v }
            return (s.crashes, s.analytics)
        }
        for (k, v) in safe {
            crashes.setTag(k, v.description)
            analytics.register(k, v)
        }
    }

    static func applyConsent(_ value: AnalyticsConsent) {
        let (before, analytics, withdrawn) = state.withLock { s in
            let before = s.consent
            s.consent = value
            // Withdrawn: what follows is anonymous again, under a new id.
            let withdrawn = value != .granted && s.identified
            if withdrawn { s.identified = false }
            return (before, s.analytics, withdrawn)
        }
        analytics.setEnabled(value != .denied)
        if withdrawn { resetAnalytics() }
        identifyIfAllowed()
        if before != value { crashes.breadcrumb(Breadcrumb(category: "consent", message: "analytics \(value.rawValue)")) }
    }

    /// A new anonymous id, with the super properties registered again on it.
    private static func resetAnalytics() {
        let (analytics, registered) = state.withLock { ($0.analytics, $0.registered) }
        analytics.reset()
        for (k, v) in registered { analytics.register(k, v) }
    }

    private static func identifyIfAllowed() {
        let target: (id: String, analytics: any Analytics)? = state.withLock { s in
            guard let id = s.userID, s.consent == .granted, !s.identified else { return nil }
            s.identified = true
            return (id, s.analytics)
        }
        if let target { target.analytics.identify(target.id) }
    }

    /// Sends what's waiting (the app is about to go to the background).
    static func flush() { analytics.flush() }

    // MARK: Errors and logs

    /// An error the code didn't expect. What's normal on a phone (offline, cancelled, a refusal the
    /// server explains to the person) only goes in the breadcrumbs: Sentry alerts on what needs a fix.
    static func unexpected(_ error: Error, _ area: String, _ action: String? = nil, extra: TelemetryProperties = [:]) {
        let (crashes, classifier) = state.withLock { ($0.crashes, $0.classifier) }
        let kind = classifier.kind(of: error)
        if kind == .cancelled { return }
        var properties = extra
        properties["kind"] = kind.rawValue
        let report = ErrorReport(area: area, action: action, extra: PrivacyGuard.properties("error", properties))
        if kind.reportable {
            crashes.capture(error, report)
        } else {
            let place = action.map { "\(area).\($0)" } ?? area
            crashes.breadcrumb(Breadcrumb(category: "error", message: "\(place): \(kind.rawValue)", level: .warning, data: report.extra))
        }
    }

    /// The kind of failure an error is (offline, refused, server...).
    static func kind(of error: Error) -> ErrorKind {
        state.withLock { $0.classifier }.kind(of: error)
    }

    /// A failure as an event property: the server's code when it gave one (`daily_like_limit`), else the
    /// kind of failure (`offline`, `server`...). Never the message.
    static func reason(_ error: Error) -> String {
        let classifier = state.withLock { $0.classifier }
        if let code = classifier.code(of: error)?.lowercased(), code.count <= 60, PrivacyGuard.isCode(code) { return code }
        return classifier.kind(of: error).rawValue
    }

    /// Something wrong without an error (a state that shouldn't happen): an event at `level`.
    static func problem(_ text: String, _ area: String, level: Level = .warning, extra: TelemetryProperties = [:]) {
        let report = ErrorReport(area: area, extra: PrivacyGuard.properties("problem", extra), fingerprint: [area, text])
        crashes.message(PrivacyGuard.scrub(text), level, report)
    }

    static func breadcrumb(_ category: String, _ message: String, level: Level = .info, data: TelemetryProperties = [:]) {
        crashes.breadcrumb(Breadcrumb(category: category, message: PrivacyGuard.scrub(message), level: level,
                                      data: PrivacyGuard.properties(category, data)))
    }

    static func log(_ level: Level, _ text: String, attributes: TelemetryProperties = [:]) {
        crashes.log(level, PrivacyGuard.scrub(text), PrivacyGuard.properties("log", attributes))
    }

    // MARK: Performance

    /// Times `body` as `operation` (a span, or a trace of its own when nothing runs yet).
    static func trace<T>(_ operation: String, _ description: String,
                         isolation: isolated (any Actor)? = #isolation,
                         _ body: (any Span) async throws -> sending T) async rethrows -> sending T {
        let span = crashes.startSpan(operation, description)
        var ok = false
        defer { span.finish(ok: ok) }
        let value = try await body(span)
        ok = true
        return value
    }
}

// MARK: Nothing installed

private struct NoCrashes: Telemetry.CrashReporter {
    func setUser(_ id: String?) {}
    func setTag(_ key: String, _ value: String?) {}
    func breadcrumb(_ crumb: Telemetry.Breadcrumb) {}
    func capture(_ error: Error, _ report: Telemetry.ErrorReport) {}
    func message(_ text: String, _ level: Telemetry.Level, _ report: Telemetry.ErrorReport) {}
    func log(_ level: Telemetry.Level, _ text: String, _ attributes: [String: TelemetryValue]) {}
    func startSpan(_ operation: String, _ description: String) -> any Telemetry.Span { NoSpan() }
}

private struct NoAnalytics: Telemetry.Analytics {
    func capture(_ name: String, _ properties: [String: TelemetryValue]) {}
    func screen(_ name: String, _ properties: [String: TelemetryValue]) {}
    func identify(_ id: String) {}
    func setPersonProperties(_ properties: [String: TelemetryValue]) {}
    func register(_ key: String, _ value: TelemetryValue) {}
    func reset() {}
    func setEnabled(_ enabled: Bool) {}
    func flush() {}
}

private struct NoSpan: Telemetry.Span {
    func setData(_ key: String, _ value: TelemetryValue) {}
    func finish(ok: Bool) {}
}
