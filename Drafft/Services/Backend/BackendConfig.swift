import Foundation

/// The drafft backend (Supabase, EU): production or staging, picked by the build configuration
/// (`Config/*.xcconfig` → Info.plist). The publishable key is public by design: it only identifies the
/// project, and row-level security decides what each person can do.
/// Never put a secret key (sb_secret_…, service_role) in the app.
enum BackendConfig {
    static let url = URL(string: info("SupabaseURL"))!
    static let publishableKey = info("SupabasePublishableKey")
    /// RevenueCat public SDK key of the matching project (its webhook feeds this backend).
    static let revenueCatAPIKey = info("RevenueCatAPIKey")
    /// How long an email code works (Auth's email OTP expiry, 1 hour everywhere).
    static let emailCodeLifetime: TimeInterval = 3600
    /// How long an SMS code works: Auth's SMS OTP expiry, per environment (`SMS_CODE_LIFETIME`, seconds).
    static let smsCodeLifetime = TimeInterval(info("SmsCodeLifetime")) ?? 600
    /// Cloudflare Turnstile public site key, for the support form sent signed out (`TURNSTILE_SITE_KEY`).
    static let turnstileSiteKey = info("TurnstileSiteKey")
    static var functionsURL: URL { url.appendingPathComponent("functions/v1") }

    private static func info(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            fatalError("\(key) missing from Info.plist: check Config/*.xcconfig")
        }
        return value
    }
}
