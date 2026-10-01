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

    /// An unfinished sign-up always resumes, whatever the entry point. `immediately`: at launch,
    /// under the splash (no keyboard to put away, nothing to wait for).
    func signIn(onboard: Bool, immediately: Bool = false) {
        let target: Phase = onboard || OnboardingStore.hasUnfinished ? .onboarding : .main
        leavingOnPurpose = false
        // Purchases follow the account (the webhook credits this id), and its balances are the server's.
        Task {
            await Store.shared.link()
            await loadWallet()
        }
        Task { await loadAccount() }
        // A finished profile on the server is the one shown in You (another device, a reinstall),
        // with its pause, hold and settings: one read.
        if target == .main {
            Task { await refreshAccount() }
            // The last known deck, likes and matches at once, then the server's.
            showCachedDiscovery()
        }
        if immediately {
            if target == .main { tab = .discover }
            phase = target
            return
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

    /// Logged in, or a password reset: to sign-up if it isn't finished (another device, a reinstall).
    /// Without an answer (offline, a server error), in as far as this iPhone knows, and to sign-up as soon
    /// as a read says it isn't finished: never left in the tabs with a profile that can't open.
    func enterAfterLogIn() async {
        if let account = await refreshAccount() {
            signIn(onboard: !account.onboarded)
            return
        }
        routeOnAccountRead = true
        signIn(onboard: false)
        Task { await routeWhenAccountRead() }
    }

    /// In the tabs without knowing whether sign-up is finished: the account is read again, less often
    /// each time, until a read answers (this loop's or any other: Realtime, back at the front), and that
    /// read brings sign-up back if it isn't finished (`routeIfUnfinished`).
    func routeWhenAccountRead() async {
        let session = sessionID
        var delay: Duration = .seconds(2)
        // Waits first: the read that just failed was the first try, and the tabs are on screen by then.
        while routeOnAccountRead {
            try? await Task.sleep(for: delay)
            guard session == sessionID, phase == .main, routeOnAccountRead else { return }
            if let account = await refreshAccount() { routeIfUnfinished(account) }
            delay = min(delay * 2, .seconds(60))
        }
    }

    /// The first account read that answers in the tabs after an unknown sign-in: to sign-up if it isn't
    /// finished. One that answers before the tabs show (sign-in's own read) leaves it to the loop's next read.
    func routeIfUnfinished(_ account: ProfileSync.Account) {
        guard routeOnAccountRead, phase == .main else { return }
        routeOnAccountRead = false
        if !account.onboarded { withAnimation(Motion.gentle) { phase = .onboarding } }
    }

    func finishOnboarding(_ profile: Profile) {
        OnboardingStore.clear()
        me = profile
        profileLoad = .loaded
        // The server's copy (photo URLs) replaces the one sign-up built, and goes to the local cache.
        Task { await refreshAccount(force: true) }
        tab = .discover
        withAnimation(Motion.gentle) { phase = .main }
        // The first deck, now that the profile is open.
        refreshDiscovery()
    }

    /// Reads the person's profile from the server (You's retry). Until it's in, You shows a loading
    /// state, or a retry if it failed: never another profile, and Edit profile can't save over the
    /// real one (`ProfileSync.loadedAccount`), even while a copy from the local cache shows.
    func loadProfile() async {
        if profileLoad != .loaded { profileLoad = .loading }
        await refreshAccount(force: true)
    }

    /// The account's own email and verified phone: from the saved session straight away, then from
    /// the server (a number verified on another device, an email changed elsewhere).
    /// It's also where a session restored at launch is checked: one the server no longer accepts
    /// (revoked, account deleted elsewhere) ends, with the message.
    func loadAccount() async {
        let session = sessionID
        apply(Backend.shared.client.auth.currentUser)
        do {
            let user = try await Backend.shared.client.auth.user()
            if session == sessionID { apply(user) }
        } catch where Backend.refusesSession(error) {
            if session == sessionID { await endSession() }
        } catch {
            // Offline, or Auth not answering: the saved session is the best we know.
        }
    }

    private func apply(_ user: User?) {
        guard let user else { return }
        if let address = user.email, !address.isEmpty { email = address }
        let phone = user.phone ?? ""
        phoneNumber = user.phoneConfirmedAt != nil && !phone.isEmpty ? PhoneCountry.display(phone) : nil
    }

    // MARK: Account (Supabase Auth)

    /// At launch: a saved session goes straight in, to sign-up if it isn't finished, without waiting
    /// for the network. The account as this iPhone last saw it shows at once (local cache), then the
    /// server's replaces it; the session itself is checked on the way (`loadAccount`: one the server
    /// no longer accepts goes back to the welcome screen, with the message).
    ///
    /// The first launch of an account on this iPhone has no copy: the server says whether sign-up is
    /// finished, but the splash waits for it `firstReadLimit` at most. Past that it goes in, and
    /// moves to sign-up if the answer, when it comes, says it isn't finished.
    func restoreSession() async {
        guard phase == .welcome, await Backend.shared.hasSession else { return }
        email = Backend.shared.client.auth.currentUser?.email ?? email
        if let cached = showCachedAccount() {
            signIn(onboard: !cached.onboarded, immediately: true)
            return
        }
        let session = sessionID
        let read = Task { await refreshAccount() }
        let answer = await Self.first(of: { await read.value }, within: Self.firstReadLimit)
        guard session == sessionID, phase == .welcome, await Backend.shared.hasSession else { return }
        switch answer {
        case .some(.some(let account)):
            signIn(onboard: !account.onboarded, immediately: true)
        default:
            // No answer yet (slow or no network): in, as far as this iPhone knows, until the server says.
            // The late read, when it answers, decides (`routeIfUnfinished`); else it's tried again.
            routeOnAccountRead = true
            signIn(onboard: false, immediately: true)
            Task {
                if let account = await read.value { routeIfUnfinished(account) }
                await routeWhenAccountRead()
            }
        }
    }

    /// How long the splash waits for the server on an account's first launch on this iPhone.
    static let firstReadLimit: Duration = .seconds(3)

    /// The value, or nil if it takes longer than `limit` (the work itself goes on).
    private static func first<T: Sendable>(of work: @escaping @Sendable () async -> T, within limit: Duration) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask { try? await Task.sleep(for: limit); return nil }
            let result = await group.next().flatMap { $0 }
            group.cancelAll()
            return result
        }
    }

    /// Follows the account's session for as long as the app runs: when it ends without the person
    /// logging out (a refresh the server refused, sessions revoked, the account deleted on another
    /// device), the app goes back to the welcome screen and says why. Logging out or deleting the
    /// account sets `leavingOnPurpose` first, so those never show the message.
    func watchSession() async {
        for await (event, _) in Backend.shared.client.auth.authStateChanges
        where event == .signedOut || event == .userDeleted {
            // However the session ended, the next sign-in registers this device's token again.
            NotificationService.shared.forgetPushTokenRegistration()
            guard phase != .welcome, !leavingOnPurpose else { continue }
            resetAccountState()
            sessionEndedNotice = true
        }
    }

    /// The saved session is no good any more (the server refused it, or it has no profile behind
    /// it): dropped from this iPhone, with the same message.
    func endSession() async {
        await Backend.shared.signOut()
        if !leavingOnPurpose { sessionEndedNotice = true }
    }

    /// `session_revoked` on the person's topic (UserChannel): sessions ended on the server (sophros "Sign
    /// out everywhere", a sign-out everywhere from another device). If this device's is one of them, it
    /// signs out now, while its token still works: the push token is dropped and purchases stop following
    /// the account. watchSession then shows "You've been logged out".
    func sessionsRevoked(_ ids: [String]) async {
        guard let mine = await Backend.shared.sessionID, ids.contains(mine) else { return }
        await Store.shared.unlink()
        await NotificationService.shared.unregisterPushToken()
        await Backend.shared.signOut()
    }

    func signOut() {
        leavingOnPurpose = true
        sessionEndedNotice = false
        Task {
            // This device stops getting the account's pushes, and its purchases stop following it.
            await Store.shared.unlink()
            await NotificationService.shared.unregisterPushToken()
            await Backend.shared.signOut()
        }
        resetAccountState()
    }

    /// Deletes the account on the server (profile, photos, matches, chats), then resets the app.
    /// Without a session nothing can be deleted: it throws, and the sheet says so.
    func deleteAccount() async throws {
        // The server revokes the session as it deletes: that end is the person's, not a surprise.
        leavingOnPurpose = true
        do {
            _ = try await Backend.shared.function("delete-account", [:])
        } catch {
            leavingOnPurpose = false
            throw error
        }
        await Store.shared.unlink()
        OnboardingStore.clear()
        resetAccountState()
        sessionEndedNotice = false
        await Backend.shared.signOut()
    }

    /// Nothing of the account stays in the app once it signs out or is deleted: the next person who
    /// signs in on this iPhone starts empty, and only sees their own profile once it's read.
    private func resetAccountState() {
        AudioPlayback.shared.stop()
        // The chat disconnects, drops this device's push registration and its offline copy.
        Task { await ChatService.shared.stop() }
        conversations = []
        clearDiscovery()
        openChatID = nil
        chatRequest = nil
        matchScreen = nil
        banner = nil
        boostBanner = nil
        sessionsInCalendar = []
        SessionCalendar.shared.forgetAll()
        SessionStore.shared.reset()
        blocked = []
        // What's still waiting stays on this iPhone for the account's next sign-in (SafetyOutbox).
        safetyRetry?.cancel()
        safetyAttempts = 0
        dataExportRequestedAt = nil
        termsConsent = .unknown
        filters = DiscoverFilters()
        clearWallet()
        me = Self.nobody
        profileLoad = .loading
        ProfileSync.loadedAccount = nil
        eraseLocalCache()
        email = ""
        phoneNumber = nil
        applyServerPause(false)
        routeOnAccountRead = false
        sessionID += 1
        withAnimation(Motion.gentle) {
            phase = .welcome
            tab = .discover
        }
    }
}
