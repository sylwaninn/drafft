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
    /// credit (`PurchaseCredit`). A failed read changes nothing (offline: the last known balances
    /// stay).
    func loadWallet() async {
        guard await Backend.shared.hasSession,
              let data = try? await Backend.shared.select("wallets?select=boosts,super_likes,premium_until,boost_ends_at"),
              let row = try? JSONDecoder().decode([WalletRow].self, from: data).first else { return }
        apply(row)
        PurchaseCredit.shared.walletChanged()
    }

    /// A wallet the server sent back (`purchase-sync`): the row itself, or under `wallet`. Whether
    /// it could be read.
    @discardableResult
    func applyWallet(_ data: Data) -> Bool {
        struct Wrapped: Decodable { let wallet: WalletRow }
        let decoder = JSONDecoder()
        guard let row = (try? decoder.decode(WalletRow.self, from: data))
            ?? (try? decoder.decode(Wrapped.self, from: data))?.wallet
            ?? (try? decoder.decode([WalletRow].self, from: data))?.first else { return false }
        apply(row)
        return true
    }

    private func apply(_ row: WalletRow) {
        boosts = row.boosts
        superLikes = row.superLikes
        premiumUntil = Self.serverDate(row.premiumUntil)
        // A boost started on another device: the one running furthest wins.
        if let end = Self.serverDate(row.boostEndsAt), end > (boostEndsAt ?? .distantPast) { boostEndsAt = end }
    }

    /// Signed out or deleted: nothing of the account's wallet stays on screen.
    func clearWallet() {
        PurchaseCredit.shared.forget()
        subscription = nil
        premiumUntil = nil
        superLikes = 0
        boosts = 0
        boostEndsAt = nil
    }

    /// Postgres timestamps (`2026-10-24T10:00:00.123456+00:00`), to the second.
    static func serverDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let whole = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: whole)
    }
}
