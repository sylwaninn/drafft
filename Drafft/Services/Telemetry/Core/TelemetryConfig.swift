import Foundation

/// The build's telemetry keys (`Config/*.xcconfig` → Info.plist). Both are public by design: a Sentry
/// DSN only lets an app send events, a PostHog project key only lets it capture. An empty value turns
/// that service off: the app works the same, nothing is sent.
struct TelemetryConfig: Sendable, Equatable {
    var sentryDSN: String
    var postHogKey: String
    /// PostHog's EU cloud (`https://eu.i.posthog.com`): the data stays in the EU, like the backend.
    var postHogHost: String
    /// "production", "staging" or "local".
    var environment: String
    /// "0.1.0"
    var version: String
    /// The build number.
    var build: String

    /// Sentry's release name, the one the build uploads its debug symbols under.
    var release: String { "so.drafft.app@\(version)+\(build)" }

    /// Off without a DSN, and with a DSN outside Sentry's EU region (the data stays in the EU).
    var hasSentry: Bool { Self.isEUDSN(sentryDSN) }
    /// Off without a key, and with a host outside PostHog's EU cloud.
    var hasPostHog: Bool { !postHogKey.isEmpty && postHogHost.hasPrefix("https://eu.") }

    /// Share of traces kept (performance): every one in staging and local, where traffic is small and
    /// each slow request matters; 20% in production, enough for percentiles at a fraction of the quota.
    var tracesSampleRate: Double { environment == "production" ? 0.2 : 1.0 }

    /// Share of lone backend requests traced (a request inside a sampled trace always is): dozens per
    /// session, so 2% in production still gives every endpoint's percentiles at scale.
    var requestSampleRate: Double { environment == "production" ? 0.02 : 1.0 }

    /// Share of traced sessions profiled (the code paths behind a slow trace).
    var profileSampleRate: Double { environment == "production" ? 0.05 : 0.0 }

    /// `https://<key>@o<org>.ingest.de.sentry.io/<project>`: a DSN of Sentry's EU region.
    static func isEUDSN(_ dsn: String) -> Bool {
        dsn.range(of: #"^https://[0-9a-f]+@o[0-9]+\.ingest\.de\.sentry\.io/[0-9]+$"#, options: .regularExpression) != nil
    }

    /// From the app's Info.plist (`SentryDSN`, `PostHogAPIKey`, `PostHogHost`, `AppEnvironment`).
    static func fromBundle(_ bundle: Bundle = .main) -> TelemetryConfig {
        func info(_ key: String) -> String { (bundle.object(forInfoDictionaryKey: key) as? String) ?? "" }
        let host = info("PostHogHost")
        let environment = info("AppEnvironment")
        return TelemetryConfig(
            sentryDSN: info("SentryDSN"),
            postHogKey: info("PostHogAPIKey"),
            postHogHost: host.isEmpty ? "https://eu.i.posthog.com" : host,
            environment: environment.isEmpty ? "production" : environment,
            version: info("CFBundleShortVersionString"),
            build: info("CFBundleVersion")
        )
    }
}
