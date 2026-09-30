import Foundation

/// When the delete sheet warns that deleting the account doesn't cancel drafft tempo.
enum SubscriptionNotice {
    /// drafft tempo's renewal as the App Store reports it (`AppModel.subscription`).
    enum Renewal: Equatable {
        case renews, ends
        /// No App Store details: RevenueCat hasn't reported for this account yet (still linking,
        /// offline), reports no active drafft tempo, or a product the app doesn't know.
        case unknown
    }

    /// - Known: shown only while it renews. A cancelled one just ends, and billing follows the App
    ///   Store, so its answer wins over the server's wallet.
    /// - Unknown: shown when the server says drafft tempo is on (`AppModel.isPremium`). Hiding it
    ///   would let someone who pays delete the account and keep being billed, with no app left to
    ///   cancel from; the warning costs nothing when it turns out to be cancelled.
    static func showsOnDelete(_ renewal: Renewal, isPremium: Bool) -> Bool {
        switch renewal {
        case .renews: true
        case .ends: false
        case .unknown: isPremium
        }
    }
}
