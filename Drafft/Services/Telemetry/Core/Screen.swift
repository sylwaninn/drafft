import Foundation

/// The screens people see, by a stable id (PostHog's `$screen_name`, Sentry's `screen` tag), the same
/// on Android. Renaming one breaks every chart built on it: add, don't rename.
enum Screen: String, Sendable, CaseIterable, TelemetryValueConvertible {
    // Signed out
    case welcome
    case emailSignUp = "email_sign_up"
    case emailLogIn = "email_log_in"
    case emailCode = "email_code"
    case passwordReset = "password_reset"
    case onboarding

    // Gates in front of the tabs
    case locationRequired = "location_required"
    case termsConsent = "terms_consent"
    case accountHold = "account_hold"

    // The tabs
    case discover
    case likes
    case sessions
    case chats
    case me

    // Pushed screens and sheets
    case profileDetail = "profile_detail"
    case match
    case chat
    case mediaViewer = "media_viewer"
    case proposeSession = "propose_session"
    case filters
    case superLikeComposer = "super_like_composer"
    case extras
    case paywall
    case subscription
    case editProfile = "edit_profile"
    case notificationSettings = "notification_settings"
    case phoneVerification = "phone_verification"
    case selfieVerification = "selfie_verification"
    case report
    case support
    case account
    case info

    var id: String { rawValue }
}
