import SwiftUI
import Supabase
import UIKit

/// Signing in and out, and deleting the account: moved out of the class body, which only keeps
/// the state they change.
extension AppModel {
    /// No one yet: what `me` holds before the server's profile is read, and after signing out.
    static let nobody = Profile(
        id: "me", name: "", age: 18, neighborhood: "", distanceKm: 0, portrait: "", photos: [], sports: [],
        voiceIntro: nil, voiceDuration: 0, icebreaker: Icebreaker.Kind.twoTruths.blank, favoriteSpot: "",
        bio: "", goal: "", vitalsOverride: .blank, promptsOverride: []
    )

    // MARK: Sign in

    /// An unfinished sign-up always resumes, whatever the entry point.
    func signIn(onboard: Bool) {
        let target: Phase = onboard || OnboardingStore.hasUnfinished ? .onboarding : .main
        // Purchases follow the account (the webhook credits this id), and its balances are the server's.
        Task {
            await Store.shared.link()
            await loadWallet()
        }
        Task { await loadAccount() }
        // A finished profile on the server is the one shown in You (another device, a reinstall).
        if target == .main {
            Task { await loadProfile() }
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
        profileLoad = .loaded
        tab = .discover
        withAnimation(Motion.gentle) { phase = .main }
    }

    /// Reads the person's profile from the server. Until it's in, You shows a loading state, or a
    /// retry if it failed: never another profile, and Edit profile can't save over the real one.
    func loadProfile() async {
        let session = sessionID
        profileLoad = .loading
        do {
            guard let saved = try await ProfileSync.load() else { throw Backend.BackendError.signedOut }
            // Signed out while it loaded: it belongs to the previous account.
            guard session == sessionID else { return }
            me = saved
            profileLoad = .loaded
        } catch {
            guard session == sessionID else { return }
            profileLoad = .failed
        }
    }

    /// The account's own email and verified phone: from the saved session straight away, then from
    /// the server (a number verified on another device, an email changed elsewhere).
    func loadAccount() async {
        let session = sessionID
        apply(Backend.shared.client.auth.currentUser)
        if let user = try? await Backend.shared.client.auth.user(), session == sessionID { apply(user) }
    }

    private func apply(_ user: User?) {
        guard let user else { return }
        if let address = user.email, !address.isEmpty { email = address }
        let phone = user.phone ?? ""
        phoneNumber = user.phoneConfirmedAt != nil && !phone.isEmpty ? PhoneCountry.display(phone) : nil
    }

    // MARK: Account (Supabase Auth)

    /// At launch: a saved session goes straight in, to sign-up if it isn't finished. A session the
    /// server no longer accepts (revoked, account deleted elsewhere) stays on the welcome screen.
    func restoreSession() async {
        guard phase == .welcome, await Backend.shared.hasSession else { return }
        do {
            _ = try await Backend.shared.client.auth.user()
        } catch is AuthError {
            await endSession()
            return
        } catch {
            // Offline: the saved session is the best we know; the tabs retry once the network is back.
        }
        guard phase == .welcome, await Backend.shared.hasSession else { return }
        email = await Backend.shared.client.auth.currentUser?.email ?? email
        let onboarded = (try? await Backend.shared.isOnboarded()) ?? true
        signIn(onboard: !onboarded)
    }

    /// Follows the account's session for as long as the app runs: when it ends without the person
    /// logging out (a refresh the server refused, sessions revoked, the account deleted on another
    /// device), the app goes back to the welcome screen and says why. Logging out or deleting the
    /// account goes back to it first, so those never show the message.
    func watchSession() async {
        for await (event, _) in Backend.shared.client.auth.authStateChanges
        where event == .signedOut || event == .userDeleted {
            guard phase != .welcome else { continue }
            resetAccountState()
            sessionEndedNotice = true
        }
    }

    /// The saved session is no good any more: dropped from this iPhone, with the same message.
    private func endSession() async {
        await Backend.shared.signOut()
        sessionEndedNotice = true
    }

    /// `session_revoked` on the person's topic (UserChannel): sessions ended on the server (sophros "Sign
    /// out everywhere", a sign-out everywhere from another device). If this device's is one of them, it
    /// signs out now, while its token still works: the push token is dropped and purchases stop following
    /// the account. watchSession then shows "You've been logged out".
    func sessionsRevoked(_ ids: [String]) async {
        guard let mine = await Backend.shared.sessionID, ids.contains(mine) else { return }
        let token = NotificationService.shared.deviceToken
        await Store.shared.unlink()
        if let token { _ = try? await Backend.shared.rpc("unregister_push_token", ["p_token": token]) }
        await Backend.shared.signOut()
    }

    func signOut() {
        let token = NotificationService.shared.deviceToken
        Task {
            // This device stops getting the account's pushes, and its purchases stop following it.
            await Store.shared.unlink()
            if let token { _ = try? await Backend.shared.rpc("unregister_push_token", ["p_token": token]) }
            await Backend.shared.signOut()
        }
        resetAccountState()
    }

    /// Deletes the account on the server (profile, photos, matches, chats), then resets the app.
    /// Without a session nothing can be deleted: it throws, and the sheet says so.
    func deleteAccount() async throws {
        _ = try await Backend.shared.function("delete-account", [:])
        await Store.shared.unlink()
        OnboardingStore.clear()
        // Back on the welcome screen before the session goes, so it isn't taken for a revoked one.
        resetAccountState()
        await Backend.shared.signOut()
    }

    /// Nothing of the account stays in the app once it signs out or is deleted: the next person who
    /// signs in on this iPhone starts empty, and only sees their own profile once it's read.
    private func resetAccountState() {
        AudioPlayback.shared.stop()
        conversations = MockData.conversations()
        queue = MockData.deck
        history = []
        pendingOpeners = [:]
        openChatID = nil
        chatRequest = nil
        matchScreen = nil
        banner = nil
        boostBanner = nil
        sessionsInCalendar = []
        SessionCalendar.shared.forgetAll()
        blocked = []
        dataExportRequestedAt = nil
        filters = DiscoverFilters()
        clearWallet()
        likesLeft = Self.dailyLikes
        me = Self.nobody
        profileLoad = .loading
        ProfileSync.loadedAccount = nil
        email = ""
        phoneNumber = nil
        applyServerPause(false)
        sessionID += 1
        withAnimation(Motion.gentle) {
            phase = .welcome
            tab = .discover
        }
    }
}
