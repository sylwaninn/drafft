import Foundation
import os

/// The account's own profile row, from one source: `refreshAccount` reads it in one request and
/// applies it everywhere it shows (You, the pause, a moderation hold, notification settings), and
/// the local cache keeps a copy so the next launch shows it before the network answers.
///
/// Read again at sign-in, when the account's Realtime channel (re)joins or says it changed
/// (`UserChannel`), and back at the front. Nothing else reads the row on its own.
extension AppModel {
    /// A read this recent is reused instead of asking again (sign-in reads it, then the screens it
    /// opens ask too).
    private static let freshFor: TimeInterval = 5

    /// Reads the account from the server and applies it. Concurrent calls share one request; `force`
    /// skips the recent-read shortcut (a live event said it changed). Nil if it couldn't be read:
    /// what's on screen stays (offline: the last known state).
    @discardableResult
    func refreshAccount(force: Bool = false) async -> ProfileSync.Account? {
        if let running = accountRefresh { return await running.value }
        if !force, let last = lastAccountRead, last.at.timeIntervalSinceNow > -Self.freshFor { return last.account }
        let session = sessionID
        let pauseEdits = pauseEdits
        let task = Task { [self] () -> ProfileSync.Account? in
            do {
                guard let (account, data) = try await ProfileSync.loadAccount() else { throw Backend.BackendError.signedOut }
                // Signed out while it loaded: it belongs to the previous account.
                guard session == sessionID else { return nil }
                openLocalCache()?.save(data, as: .profile)
                lastAccountRead = (.now, account)
                apply(account, pauseReadAt: pauseEdits)
                applyConsent(fromServer: account.consent)
                routeIfUnfinished(account)
                return account
            } catch {
                guard session == sessionID else { return nil }
                Telemetry.unexpected(error, "account", "refresh")
                Self.accountLog.error("The account couldn't be read: \(String(describing: error))")
                if profileLoad != .loaded {
                    profileLoadFailure = ServerMessage.text(for: error, offline: L("Check your connection and try again."))
                    profileLoad = .failed
                }
                retryWhileConsentUnknown()
                return nil
            }
        }
        accountRefresh = task
        let account = await task.value
        if session == sessionID { accountRefresh = nil }
        return account
    }

    /// The account as this iPhone last saw it, applied at once (launch). Nil without a copy.
    func showCachedAccount() -> ProfileSync.Account? {
        guard let entry = openLocalCache()?.entry(.profile),
              let account = ProfileSync.decodeAccount(entry.data, mediaBase: MediaURL.saved) else { return nil }
        apply(account)
        // A cached "accepted" holds (the consent is only withdrawn by deleting the account); a
        // cached "required" may be out of date: only the server's read asks.
        if account.consent == .accepted, termsConsent == .unknown { termsConsent = .accepted }
        return account
    }

    private static let accountLog = AppLog("account")

    /// The gate from a fresh read. A backend without the consent columns leaves it as it was
    /// (ProfileSync logs that).
    private func applyConsent(fromServer consent: TermsConsent.Gate) {
        accountReadFailures = 0
        accountRetry?.cancel()
        accountRetry = nil
        if consent != .unknown { termsConsent = consent }
    }

    /// While the consent is unknown, a failed read is tried again after 5 s, then 10, 20… up to 5
    /// minutes, until one succeeds or the account changes: an account that never consented isn't
    /// left unasked because the first read failed.
    private func retryWhileConsentUnknown() {
        guard termsConsent == .unknown, accountRetry == nil else { return }
        let delay = min(300, 5 * pow(2, Double(min(accountReadFailures, 6))))
        accountReadFailures += 1
        let session = sessionID
        accountRetry = Task { [self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, session == sessionID else { return }
            accountRetry = nil
            await refreshAccount(force: true)
        }
    }

    private func apply(_ account: ProfileSync.Account, pauseReadAt: Int? = nil) {
        // Before the profile: a refused or pending photo must never show as the profile, not even for a frame.
        PhotoModeration.shared.track(account.photos)
        me = account.profile
        profileLoad = .loaded
        applyServerPause(account.paused, readAt: pauseReadAt)
        AccountModeration.shared.apply(account.hold)
        if let settings = account.notifications { NotificationService.shared.applyServer(settings) }
    }

    /// The signed-in account's cache, opened on first use (nil signed out, or if the file can't be
    /// opened: the app then simply works without it).
    @discardableResult
    func openLocalCache() -> LocalCache? {
        guard let id = Backend.shared.client.auth.currentUser?.id else { return nil }
        if let cache = localCache, cache.account == id { return cache }
        localCache = try? LocalCache(account: id)
        return localCache
    }

    /// Signed out or deleted: nothing of the account stays on this iPhone.
    func eraseLocalCache() {
        accountRefresh?.cancel()
        accountRefresh = nil
        accountRetry?.cancel()
        accountRetry = nil
        accountReadFailures = 0
        lastAccountRead = nil
        localCache = nil
        LocalCache.eraseAll()
    }
}
