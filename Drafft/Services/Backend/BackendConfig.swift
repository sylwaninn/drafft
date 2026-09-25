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
    /// Whether Supabase Auth texts codes (the environment's Send SMS hook is set up). Off: the phone step
    /// runs the demo. Per environment, from `SMS_ENABLED` in Config/*.xcconfig.
    static let smsEnabled = info("SmsEnabled") == "YES"
    static var functionsURL: URL { url.appendingPathComponent("functions/v1") }

    private static func info(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            fatalError("\(key) missing from Info.plist: check Config/*.xcconfig")
        }
        return value
    }
}
