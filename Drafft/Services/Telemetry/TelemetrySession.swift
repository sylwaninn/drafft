import Foundation
import Supabase

/// Installs `Telemetry`'s engines and keeps it in step with the account: who is signed in (Supabase
/// Auth's session, the one source), and the few facts dashboards split by (language, drafft tempo,
/// where the person is in the app). docs/telemetry.md is the plan.
@MainActor
enum TelemetrySession {
    static let config = TelemetryConfig.fromBundle()

    /// First thing at launch, before anything that could crash: Sentry, then PostHog with the person's
    /// saved answer. Without keys nothing is installed and every call does nothing.
    static func start() {
        Telemetry.install(crashes: SentryCrashReporter.start(config), classifier: AppErrorClassifier())
        let consent = AnalyticsConsent.load()
        Telemetry.install(analytics: PostHogAnalytics.start(config, optedOut: consent == .denied))
        Telemetry.applyConsent(consent)
        Telemetry.register("app_environment", config.environment)
    }

    static var consent: AnalyticsConsent { Telemetry.consent }

    /// The person's answer (You › Privacy & data), kept on the phone and applied at once.
    static func setConsent(_ value: AnalyticsConsent) {
        guard value != Telemetry.consent else { return }
        AnalyticsConsent.save(value)
        // Applied first: after a refusal not even the refusal is sent (PostHog gets nothing, Sentry no breadcrumb).
        Telemetry.applyConsent(value)
        Telemetry.track(.analyticsConsentChanged(value))
    }

    /// The signed-in account, for as long as the app runs. A session read back from the phone counts:
    /// it's the account the app shows.
    static func watchAccount() async {
        for await (event, session) in Backend.shared.client.auth.authStateChanges {
            switch event {
            case .signedOut, .userDeleted: Telemetry.signedIn(nil)
            default:
                if let id = session?.user.id { Telemetry.signedIn(id.uuidString.lowercased()) }
            }
        }
    }

    /// What every event and error report carries about the app's state.
    static func describe(_ app: AppModel) {
        Telemetry.register("app_language", app.language.rawValue)
        Telemetry.register("app_phase", phaseID(app.phase))
        Telemetry.register("is_premium", app.isPremium)
        Telemetry.describeAccount(["is_premium": app.isPremium, "language": app.language.rawValue])
    }

    /// The screen under any sheet or pushed screen: welcome, sign-up, or the current tab. While the tabs
    /// are walked invisibly (`prebuilding`) it stays on Discover: nobody sees the others.
    static func baseScreen(_ app: AppModel, prebuilding: Bool = false) -> Screen {
        if prebuilding, app.phase == .main { return .discover }
        return switch app.phase {
        case .welcome: .welcome
        case .onboarding: .onboarding
        case .main:
            switch app.tab {
            case .discover: .discover
            case .likes: .likes
            case .sessions: .sessions
            case .chats: .chats
            case .me: .me
            }
        }
    }

    static func phaseID(_ phase: AppModel.Phase) -> String {
        switch phase {
        case .welcome: "welcome"
        case .onboarding: "onboarding"
        case .main: "main"
        }
    }
}
