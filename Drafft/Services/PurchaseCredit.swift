import Foundation

/// Purchases the App Store confirmed that the server hasn't credited yet.
///
/// Right after Apple confirms, the app asks the backend to credit it at once (`purchase-sync`, which
/// reads the purchase from RevenueCat and returns the wallet and whether that transaction is
/// credited); the webhook does the same on its own.
/// The usual case takes a second or two and the purchase screen shows its confirmation. Past
/// `buttonWait`, the button is free again and a banner at the top (`TopOverlayWindow`) says the
/// purchase is being added; it never says the payment went through.
///
/// Each pending purchase is kept per account (transaction, product, date) until the wallet has it,
/// so a relaunch, a return to the front or a reconnection asks again, with a backoff. Signing out
/// or deleting the account forgets them.
@MainActor
@Observable
final class PurchaseCredit {
    static let shared = PurchaseCredit()

    struct Pending: Codable, Equatable {
        /// What the wallet shows once it's credited.
        enum Target: Codable, Equatable {
            case boosts(atLeast: Int)
            case superLikes(atLeast: Int)
            case tempo
        }

        let transactionID: String?
        let productID: String
        let date: Date
        let target: Target

        @MainActor func isCredited(in app: AppModel) -> Bool {
            switch target {
            case .boosts(let count): app.boosts >= count
            case .superLikes(let count): app.superLikes >= count
            case .tempo: app.isPremium
            }
        }
    }

    enum Banner: Equatable { case adding, credited }

    /// Oldest first.
    private(set) var pending: [Pending] = []
    /// What the top banner shows, if anything.
    private(set) var banner: Banner?
    /// Past this, the banner offers to contact support.
    static let slowAfter: TimeInterval = 10 * 60

    /// Swiped away: it shows again at the next launch only.
    @ObservationIgnored private var dismissedThisLaunch = false
    @ObservationIgnored private var userID: String?
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var sync: Task<Void, Never>?
    @ObservationIgnored private var hideCredited: Task<Void, Never>?
    /// The pending purchases read back from the phone: the app may have been away for days, so how
    /// long they took to credit says nothing about the server.
    @ObservationIgnored private var restored: [Pending] = []

    private static let buttonWait: Duration = .seconds(8)
    private static let backoff: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(60)]
    private static let steadyRetry: Duration = .seconds(5 * 60)
    /// Throttled or down: the webhook will credit it, ask again no sooner than this.
    private static let throttledRetry: Duration = .seconds(60)

    var oldest: Pending? { pending.first }

    /// "Contact us" on the banner: "Get help", filled in for the oldest pending purchase.
    func contactSupport() {
        guard let app else { return }
        PurchaseHelpPresenter.show(oldest, app: app)
    }

    // MARK: Purchase screens

    /// The App Store confirmed `purchase`: asks the server to credit it and waits up to 8 s.
    /// Whether it's on the account (the screen then shows its confirmation); if not, the banner
    /// takes over and the screen frees its button.
    func confirmed(_ purchase: Pending, app: AppModel) async -> Bool {
        attach(app, userID: Store.shared.linkedUserID)
        if purchase.isCredited(in: app) { return true }
        pending.append(purchase)
        save()
        runSync()
        let clock = ContinuousClock()
        let deadline = clock.now + Self.buttonWait
        while clock.now < deadline {
            if !pending.contains(purchase) { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if !pending.contains(purchase) { return true }
        // A new purchase shows the banner, even if an earlier one was swiped away.
        dismissedThisLaunch = false
        show(.adding)
        return false
    }

    // MARK: Lifecycle

    /// Launch, return to the front, Realtime reconnection: asks again for anything still pending
    /// on this account, and shows the banner unless it was swiped away since launch.
    func resume(_ app: AppModel) async {
        guard let id = await Backend.shared.userID?.uuidString.lowercased() else { return }
        attach(app, userID: id)
        guard !pending.isEmpty else { return }
        if !dismissedThisLaunch { show(.adding) }
        runSync()
    }

    /// The wallet was read again (`AppModel.loadWallet`): drops whatever it now holds.
    func walletChanged() {
        guard let app, !pending.isEmpty else { return }
        let before = pending.count
        let credited = pending.filter { $0.isCredited(in: app) }
        for purchase in credited { trackCredited(purchase) }
        pending.removeAll { credited.contains($0) }
        guard pending.count != before else { return }
        save()
        if pending.isEmpty {
            sync?.cancel()
            // A purchase screen still waiting shows its own confirmation; otherwise the banner does.
            if banner == .adding { show(.credited) }
        }
    }

    func dismissBanner() {
        dismissedThisLaunch = true
        hideCredited?.cancel()
        banner = nil
    }

    /// Sign-out or account deletion: nothing of the account stays on this device.
    func forget() {
        sync?.cancel()
        hideCredited?.cancel()
        if let userID { UserDefaults.standard.removeObject(forKey: Self.key(userID)) }
        userID = nil
        pending = []
        restored = []
        banner = nil
        dismissedThisLaunch = false
    }

    // MARK: Private

    private func attach(_ app: AppModel, userID id: String?) {
        self.app = app
        guard let id, id != userID else { return }
        sync?.cancel()
        userID = id
        pending = Self.load(id)
        restored = pending
        banner = nil
    }

    private func show(_ state: Banner) {
        hideCredited?.cancel()
        banner = state
        guard state == .credited else { return }
        Haptics.success()
        hideCredited = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, banner == .credited else { return }
            banner = nil
        }
    }

    /// Asks now, then after 2 s, 5 s, 15 s, 60 s, then every 5 minutes, until nothing is pending.
    private func runSync() {
        sync?.cancel()
        sync = Task { [weak self] in
            var step = 0
            while !Task.isCancelled {
                guard let self, !self.pending.isEmpty else { return }
                let atLeast = await self.syncOnce()
                guard !Task.isCancelled, !self.pending.isEmpty else { return }
                var delay = step < Self.backoff.count ? Self.backoff[step] : Self.steadyRetry
                if let atLeast { delay = max(delay, atLeast) }
                step += 1
                try? await Task.sleep(for: delay)
            }
        }
    }

    /// One `purchase-sync` call. The shortest wait before the next one, when the server asked for it.
    private func syncOnce() async -> Duration? {
        guard let app, let purchase = pending.first else { return nil }
        var body: [String: Any] = [:]
        if let id = purchase.transactionID { body["transaction_id"] = id }
        do {
            let data = try await Backend.shared.function("purchase-sync", body)
            // The wallet it returns; a shape it doesn't know reads the row instead.
            if !app.applyWallet(data) { await app.loadWallet() }
            // The server says whether this transaction is credited: that answer wins. Without it (an
            // older server, no transaction id), the balances tell.
            if let id = purchase.transactionID, let status = Self.status(of: id, in: data) {
                if status == .credited { markCredited(purchase) }
            } else {
                walletChanged()
            }
            return nil
        } catch {
            await app.loadWallet()
            // Too many asks, or the store is slow to answer: the webhook credits it meanwhile. Expected,
            // so not an error report.
            if case Backend.BackendError.http(let status, _) = error, status == 429 || status == 503 {
                Telemetry.breadcrumb("purchase", "purchase_sync throttled: \(status)", level: .warning)
                return Self.throttledRetry
            }
            Telemetry.unexpected(error, "purchase", "purchase_sync")
            return nil
        }
    }

    private enum ServerStatus { case credited, notYet }

    /// `purchase-sync` answers `{ wallet, transaction: { id, credited } }`: whether `id` is credited,
    /// or nil when the answer doesn't say (no `transaction`, another id).
    private static func status(of id: String, in data: Data) -> ServerStatus? {
        struct Answer: Decodable {
            struct Transaction: Decodable {
                let id: String
                let credited: Bool
            }
            let transaction: Transaction?
        }
        guard let transaction = (try? JSONDecoder().decode(Answer.self, from: data))?.transaction,
              transaction.id == id else { return nil }
        return transaction.credited ? .credited : .notYet
    }

    /// The server credited `purchase`: it leaves the list, whatever the balances say.
    private func markCredited(_ purchase: Pending) {
        if pending.contains(purchase) { trackCredited(purchase) }
        pending.removeAll { $0 == purchase }
        walletChanged()
        save()
        if pending.isEmpty {
            sync?.cancel()
            if banner == .adding { show(.credited) }
        }
    }

    private func trackCredited(_ purchase: Pending) {
        let seconds = max(0, Int(Date.now.timeIntervalSince(purchase.date)))
        Telemetry.track(.purchaseCredited(seconds: seconds))
        // Paid and only credited long after: the webhook or purchase-sync is late, worth a look. Not for
        // one read back from the phone after the app was closed: that wait is the person's.
        if TimeInterval(seconds) > Self.slowAfter, !restored.contains(purchase) {
            Telemetry.problem("purchase credited late", "purchase", extra: ["seconds_to_credit": seconds])
        }
    }

    private static func key(_ userID: String) -> String { "purchaseCredit.pending.\(userID)" }

    private static func load(_ userID: String) -> [Pending] {
        guard let data = UserDefaults.standard.data(forKey: key(userID)) else { return [] }
        return (try? JSONDecoder().decode([Pending].self, from: data)) ?? []
    }

    private func save() {
        guard let userID else { return }
        if pending.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.key(userID))
        } else if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.key(userID))
        }
    }
}
