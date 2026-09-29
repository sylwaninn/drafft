import Foundation

/// The terms and the consent to sensitive data, recorded on the server (`accept_terms`): the version
/// of the terms accepted and when, and when the consent was given. Gender and the genders someone
/// wants to see can reveal their sexual orientation, lifestyle answers their health: drafft uses them
/// on explicit consent, which it must be able to show. Sign-up records both on the ground rules step;
/// an account that has neither for the current version is asked once, at its next open
/// (`TermsConsentView`). `complete_onboarding` refuses a sign-up without them (`terms_required`).
enum TermsConsent {
    /// The version of the terms on getdrafft.com the app shows. A newer one asks everyone again.
    static let version = "2026-09-29"

    /// Records both, now. Throws the server's refusal (`sensitive_consent_required`).
    static func accept() async throws {
        _ = try await Backend.shared.rpc("accept_terms", ["p_version": version, "p_sensitive_consent": true])
    }

    /// Whether an account still has to accept: terms older than this version, or no consent on file.
    /// Versions are dates, so they compare as text.
    static func isNeeded(acceptedVersion: String?, sensitiveConsentAt: String?) -> Bool {
        (acceptedVersion ?? "") < version || sensitiveConsentAt == nil
    }
}
