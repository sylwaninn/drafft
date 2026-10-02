import Foundation
import os

extension TermsConsent {
    static let log = AppLog("consent")

    /// Records both, now: the terms at `version` and the consent (always given, so the server's
    /// `sensitive_consent_required` can't come back from here). Throws on a network error or the
    /// server's refusal (`unauthenticated`, `not_found`, `invalid_terms_version`); `failure(for:)`
    /// says what to do with it. `during`: where they're asked (`sign_up`, `gate`), for analytics.
    static func accept(during: String) async throws {
        do {
            _ = try await Backend.shared.rpc("accept_terms", ["p_version": version, "p_sensitive_consent": true])
        } catch {
            // Sign-up can't leave its rules step without them.
            if during == "sign_up" { Telemetry.track(.onboardingStepBlocked(step: "rules", reason: Telemetry.reason(error))) }
            Telemetry.unexpected(error, during == "sign_up" ? "onboarding" : "account", "accept_terms")
            throw error
        }
        Telemetry.track(.termsAccepted(version: version, during: during))
    }

    /// What to do after `accept()` threw, logged: the code or error never reaches the screen.
    static func failure(for error: Error) -> Failure {
        if case Backend.BackendError.signedOut = error {
            log.error("accept_terms without a session")
            return .signOut
        }
        let code = ServerMessage.code(of: error)
        log.error("accept_terms failed: \(code ?? String(describing: error))")
        return failure(code: code, offline: error is URLError)
    }
}
