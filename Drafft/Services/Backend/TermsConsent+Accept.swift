import Foundation
import os

extension TermsConsent {
    static let log = Logger(subsystem: "so.drafft.app", category: "consent")

    /// Records both, now: the terms at `version` and the consent (always given, so the server's
    /// `sensitive_consent_required` can't come back from here). Throws on a network error or the
    /// server's refusal (`unauthenticated`, `not_found`, `invalid_terms_version`); `failure(for:)`
    /// says what to do with it.
    static func accept() async throws {
        _ = try await Backend.shared.rpc("accept_terms", ["p_version": version, "p_sensitive_consent": true])
    }

    /// What to do after `accept()` threw, logged: the code or error never reaches the screen.
    static func failure(for error: Error) -> Failure {
        if case Backend.BackendError.signedOut = error {
            log.error("accept_terms without a session")
            return .signOut
        }
        let code = ServerMessage.code(of: error)
        log.error("accept_terms failed: \(code ?? String(describing: error), privacy: .public)")
        return failure(code: code, offline: error is URLError)
    }
}
