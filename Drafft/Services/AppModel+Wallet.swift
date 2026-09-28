import Foundation

/// The account's wallet: drafft tempo, boosts and super likes, as the server has them.
extension AppModel {
    func balance(of item: Consumable) -> Int {
        switch item {
        case .boost: boosts
        case .superLike: superLikes
        }
    }

    // MARK: Wallet (server)

    fileprivate struct WalletRow: Decodable {
        let boosts: Int
        let superLikes: Int
        let premiumUntil: String?
        let boostEndsAt: String?
        enum CodingKeys: String, CodingKey {
            case boosts
            case superLikes = "super_likes"
            case premiumUntil = "premium_until"
            case boostEndsAt = "boost_ends_at"
        }
    }

    /// Reads the account's own wallet row (RLS: only its own). At sign-in, on each Realtime
    /// (re)connection and `wallet` event, back at the front, and while a purchase waits for its
    /// credit. A failed read changes nothing (offline: the last known balances stay).
    func loadWallet() async {
        guard await Backend.shared.hasSession,
              let data = try? await Backend.shared.select("wallets?select=boosts,super_likes,premium_until,boost_ends_at"),
              let row = try? JSONDecoder().decode([WalletRow].self, from: data).first else { return }
        boosts = row.boosts
        superLikes = row.superLikes
        premiumUntil = Self.serverDate(row.premiumUntil)
        // A boost started on another device: the one running furthest wins.
        if let end = Self.serverDate(row.boostEndsAt), end > (boostEndsAt ?? .distantPast) { boostEndsAt = end }
    }

    /// After a payment: reads the wallet until the server has credited it (App Store, RevenueCat,
    /// then the webhook), for up to `timeout`. Whether it arrived in time.
    func waitForWallet(timeout: Duration = .seconds(45), until credited: (AppModel) -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var pause = Duration.seconds(1)
        while clock.now < deadline {
            await loadWallet()
            if credited(self) { return true }
            try? await Task.sleep(for: pause)
            pause = min(pause * 2, .seconds(5))
        }
        await loadWallet()
        return credited(self)
    }

    /// The credit is late (the store or the webhook): keep reading, more slowly, for a few minutes
    /// more, so it shows without a trip out of the app. Realtime and the next return to the front
    /// catch it after that.
    func keepWaitingForWallet(until credited: @escaping @MainActor (AppModel) -> Bool) {
        let session = sessionID
        Task {
            for _ in 0..<20 {
                try? await Task.sleep(for: .seconds(15))
                guard session == sessionID else { return }
                await loadWallet()
                if credited(self) { return }
            }
        }
    }

    /// Signed out or deleted: nothing of the account's wallet stays on screen.
    func clearWallet() {
        subscription = nil
        premiumUntil = nil
        superLikes = 0
        boosts = 0
        boostEndsAt = nil
    }

    /// Postgres timestamps (`2026-10-24T10:00:00.123456+00:00`), to the second.
    private static func serverDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let whole = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: whole)
    }
}
