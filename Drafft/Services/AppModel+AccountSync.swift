import Foundation

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
        let task = Task { [self] () -> ProfileSync.Account? in
            do {
                guard let (account, data) = try await ProfileSync.loadAccount() else { throw Backend.BackendError.signedOut }
                // Signed out while it loaded: it belongs to the previous account.
                guard session == sessionID else { return nil }
                openLocalCache()?.save(data, as: .profile)
                lastAccountRead = (.now, account)
                apply(account)
                // Only from the server: a cached copy may predate the consent or lack it.
                termsConsentNeeded = account.termsNeeded
                return account
            } catch {
                guard session == sessionID else { return nil }
                if profileLoad != .loaded { profileLoad = .failed }
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
        return account
    }

    private func apply(_ account: ProfileSync.Account) {
        me = account.profile
        profileLoad = .loaded
        applyServerPause(account.paused)
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
        lastAccountRead = nil
        localCache = nil
        LocalCache.eraseAll()
    }
}
