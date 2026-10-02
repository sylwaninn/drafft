import Foundation

/// What the person said about usage analytics (PostHog), kept on the phone.
///
/// - `unknown` (not asked yet): events go without the account, under a random id of this install that
///   a sign-out renews. Audience measurement the person can object to (the privacy policy says how).
/// - `granted`: events are linked to the account's id (the same pseudonymous id as Sentry, RevenueCat
///   and the backend), so a journey can be followed across devices and support can find it.
/// - `denied`: nothing goes to PostHog. Crash and error reports (Sentry) still go: they keep the
///   service working and safe, and carry no usage.
///
/// Asking belongs to You › Privacy & data (docs/telemetry.md); `TelemetrySession.setConsent` applies it.
enum AnalyticsConsent: String, Sendable, CaseIterable, TelemetryValueConvertible {
    case unknown
    case granted
    case denied

    static let key = "telemetry.analyticsConsent"

    static func load(_ defaults: UserDefaults = .standard) -> AnalyticsConsent {
        defaults.string(forKey: key).flatMap(AnalyticsConsent.init(rawValue:)) ?? .unknown
    }

    static func save(_ value: AnalyticsConsent, _ defaults: UserDefaults = .standard) {
        defaults.set(value.rawValue, forKey: key)
    }
}
