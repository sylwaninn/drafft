import Foundation
import RevenueCat

/// In-app purchases, through RevenueCat. Prices are never written in the app: App Store Connect
/// sets them, RevenueCat's offerings decide which products show, and the App Store formats them
/// for the person's country.
///
/// - `default` offering: the drafft tempo plans (entitlement `drafft_tempo`).
/// - `boosts` and `super_likes` offerings: the consumable packs. A pack's size is the last part
///   of its product ID (`so.drafft.app.boost.5` is 5 boosts).
@MainActor
@Observable
final class Store {
    static let shared = Store()
    static let tempoEntitlement = "drafft_tempo"

    enum LoadState { case idle, loading, loaded, failed }
    private(set) var state: LoadState = .idle
    private(set) var tempo: [PaywallView.Plan: Package] = [:]
    private(set) var boosts: [Package] = []
    private(set) var superLikes: [Package] = []

    /// Once, at launch, before anything reads purchases.
    static func configure() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        // Public SDK key (safe in the app): RevenueCat project "drafft" or "drafft staging".
        Purchases.configure(withAPIKey: BackendConfig.revenueCatAPIKey)
    }

    /// Fetches the offerings. Does nothing while a load runs or once loaded; a failed load runs again.
    func load() async {
        guard state != .loading && state != .loaded else { return }
        state = .loading
        do {
            let offerings = try await Purchases.shared.offerings()
            var plans: [PaywallView.Plan: Package] = [:]
            for package in offerings.current?.availablePackages ?? [] {
                if let plan = PaywallView.Plan(productID: package.storeProduct.productIdentifier) {
                    plans[plan] = package
                }
            }
            tempo = plans
            boosts = Self.packs(offerings.offering(identifier: "boosts"))
            superLikes = Self.packs(offerings.offering(identifier: "super_likes"))
            state = plans.isEmpty && boosts.isEmpty && superLikes.isEmpty ? .failed : .loaded
        } catch {
            state = .failed
        }
    }

    enum Outcome { case purchased(CustomerInfo), cancelled }

    func purchase(_ package: Package) async throws -> Outcome {
        let result = try await Purchases.shared.purchase(package: package)
        return result.userCancelled ? .cancelled : .purchased(result.customerInfo)
    }

    func restore() async throws -> CustomerInfo {
        try await Purchases.shared.restorePurchases()
    }

    /// How many boosts or super likes a pack holds.
    static func count(of package: Package) -> Int {
        Int(package.storeProduct.productIdentifier.split(separator: ".").last ?? "") ?? 1
    }

    /// drafft tempo as the App Store reports it, or nil when it isn't active.
    func subscription(from info: CustomerInfo) -> TempoSubscription? {
        guard let e = info.entitlements[Self.tempoEntitlement], e.isActive,
              let plan = PaywallView.Plan(productID: e.productIdentifier) else { return nil }
        let price = tempo[plan]?.storeProduct.localizedPriceString
        var sub = TempoSubscription(plan: plan, started: e.latestPurchaseDate ?? .now,
                                    billing: price.map(plan.billing) ?? plan.title)
        if let end = e.expirationDate { sub.periodEnds = end }
        sub.willRenew = e.willRenew
        return sub
    }

    private static func packs(_ offering: Offering?) -> [Package] {
        (offering?.availablePackages ?? []).sorted { count(of: $0) < count(of: $1) }
    }
}
