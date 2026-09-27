#if LOCAL_BACKEND
import Foundation
import OSLog

/// Local builds only (never staging or production): signs in to a local test account at launch, so a
/// device test starts where it matters. The credentials come from the launch environment (devicectl
/// `--environment-variables`, or the Xcode scheme), never from the code:
///   DRAFFT_TEST_EMAIL, DRAFFT_TEST_PASSWORD
/// With `-openSelfie`, the selfie camera opens by itself once the selfie hold shows (AccountHoldView).
enum LocalLaunch {
    @MainActor
    static func signIn(_ app: AppModel) async {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["DRAFFT_TEST_EMAIL"], let password = env["DRAFFT_TEST_PASSWORD"] else { return }
        let current = await Backend.shared.client.auth.currentUser?.email
        if current?.lowercased() != email.lowercased() {
            if current != nil { app.signOut() }
            do { try await Backend.shared.signIn(email: email, password: password) } catch {
                Logger(subsystem: "so.drafft.app", category: "LocalLaunch")
                    .error("sign-in failed for \(email, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        await app.restoreSession()
    }
}
#endif
