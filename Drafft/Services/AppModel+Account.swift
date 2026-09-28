import SwiftUI
import UIKit

/// Signing in and out, and deleting the account: moved out of the class body, which only keeps
/// the state they change.
extension AppModel {
    // MARK: Auth (demo: no backend, every path succeeds after a short beat)

    /// An unfinished sign-up always resumes, whatever the entry point.
    func signIn(onboard: Bool) {
        let target: Phase = onboard || OnboardingStore.hasUnfinished ? .onboarding : .main
        // A finished profile on the server is the one shown in You (another device, a reinstall).
        if target == .main {
            Task { if let saved = try? await ProfileSync.load() { me = saved } }
            Task { await loadPause() }
        }
        // Put the keyboard away first, so the next screen lays out at full height.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            // The tabs were walked through in the background (see RootView): land on Discover.
            if target == .main { tab = .discover }
            withAnimation(Motion.gentle) { phase = target }
        }
    }

    func finishOnboarding(_ profile: Profile) {
        OnboardingStore.clear()
        me = profile
        tab = .discover
        withAnimation(Motion.gentle) { phase = .main }
    }

    // MARK: Account (Supabase Auth)

    /// At launch: a saved session goes straight in, to sign-up if it isn't finished.
    func restoreSession() async {
        guard phase == .welcome, await Backend.shared.hasSession else { return }
        email = await Backend.shared.client.auth.currentUser?.email ?? email
        let onboarded = (try? await Backend.shared.isOnboarded()) ?? true
        signIn(onboard: !onboarded)
    }

    /// Why a link from an auth email didn't work.
    enum AuthLinkProblem: String, Identifiable {
        /// A reset link that expired, was used, was replaced by a newer one, or was opened on
        /// another device than the one that asked for it.
        case resetExpired
        /// The same for a sign-up confirmation link.
        case confirmExpired
        /// No connection: the link may still be good.
        case offline
        var id: String { rawValue }
    }

    /// A link from an auth email: a confirmed sign-up goes on to sign-up, a reset asks for the new
    /// password. A link that can't be used says so, with a way to get a new one or help.
    func handleAuthLink(_ url: URL) async {
        let link: Backend.AuthLink
        do {
            link = try await Backend.shared.handleAuthLink(url)
        } catch {
            Haptics.warning()
            if error is URLError {
                authLinkProblem = .offline
            } else {
                authLinkProblem = url.path == Backend.resetCallback.path ? .resetExpired : .confirmExpired
            }
            return
        }
        switch link {
        case .confirmed:
            email = await Backend.shared.client.auth.currentUser?.email ?? email
            if phase == .welcome { signIn(onboard: true) }
        case .resetPassword:
            choosingNewPassword = true
        }
    }

    func signOut() {
        let token = NotificationService.shared.deviceToken
        Task {
            // This device stops getting the account's pushes.
            if let token { _ = try? await Backend.shared.rpc("unregister_push_token", ["p_token": token]) }
            await Backend.shared.signOut()
        }
        AudioPlayback.shared.stop()
        sessionID += 1
        withAnimation(Motion.gentle) {
            phase = .welcome
            tab = .discover
        }
    }

    /// Deletes the account on the server (profile, photos, matches, chats), then resets the app.
    func deleteAccount() async throws {
        if await Backend.shared.hasSession {
            _ = try await Backend.shared.function("delete-account", [:])
            await Backend.shared.signOut()
        }
        resetAfterAccountDeletion()
    }

    private func resetAfterAccountDeletion() {
        AudioPlayback.shared.stop()
        conversations = MockData.conversations()
        queue = MockData.deck
        history = []
        blocked = []
        dataExportRequestedAt = nil
        filters = DiscoverFilters()
        subscription = nil
        likesLeft = Self.dailyLikes
        superLikes = 0
        boosts = 0
        boostEndsAt = nil
        me = MockData.me
        sessionID += 1
        withAnimation(Motion.gentle) {
            phase = .welcome
            tab = .discover
        }
    }
}
