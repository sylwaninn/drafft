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

    /// The account purchases are made for: the Supabase user id, lowercased, as RevenueCat's app
    /// user id. The server's webhook credits that id's wallet and ignores any other (an anonymous
    /// purchase would be paid and never credited), so nothing can be bought while this is nil.
    private(set) var linkedUserID: String?
    var isLinked: Bool { linkedUserID != nil }
    /// Bumped on sign-out: a log-in still on its way for the previous account is undone.
    @ObservationIgnored private var linkGeneration = 0

    enum StoreError: Error { case notLinked }

    /// Once, at launch, before anything reads purchases.
    static func configure() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        // Public SDK key (safe in the app): RevenueCat project "drafft" or "drafft staging".
        Purchases.configure(withAPIKey: BackendConfig.revenueCatAPIKey)
    }

    /// Links RevenueCat to the signed-in account (`Purchases.logIn`). Called at every sign-in or
    /// restored session, and again before a purchase if it hadn't gone through (offline).
    @discardableResult
    func link() async -> Bool {
        guard let id = await Backend.shared.userID?.uuidString.lowercased() else {
            linkedUserID = nil
            return false
        }
        if linkedUserID == id, Purchases.shared.appUserID == id { return true }
        let generation = linkGeneration
        do {
            if Purchases.shared.appUserID != id { _ = try await Purchases.shared.logIn(id) }
        } catch {
            linkedUserID = nil
            return false
        }
        // Signed out while it ran: this device no longer belongs to that account.
        guard generation == linkGeneration else {
            if Purchases.shared.appUserID == id { _ = try? await Purchases.shared.logOut() }
            return false
        }
        linkedUserID = id
        return true
    }

    /// Sign-out and account deletion: purchases on this device stop following the account.
    func unlink() async {
        linkGeneration += 1
        linkedUserID = nil
        guard !Purchases.shared.isAnonymous else { return }
        _ = try? await Purchases.shared.logOut()
    }

    /// Links the account, then fetches the offerings. Does nothing while a load runs or once both
    /// are done; a failed load (either part) runs again.
    func load() async {
        guard state != .loading, !(state == .loaded && isLinked) else { return }
        state = .loading
        let linked = await link()
        if tempo.isEmpty && boosts.isEmpty && superLikes.isEmpty {
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
            } catch {
                state = .failed
                return
            }
        }
        let empty = tempo.isEmpty && boosts.isEmpty && superLikes.isEmpty
        state = linked && !empty ? .loaded : .failed
    }

    enum Outcome { case purchased(CustomerInfo), cancelled }

    /// Only for the linked account. What was bought shows once the server has credited it (the
    /// wallet), never from here.
    func purchase(_ package: Package) async throws -> Outcome {
        guard await link() else { throw StoreError.notLinked }
        let result = try await Purchases.shared.purchase(package: package)
        return result.userCancelled ? .cancelled : .purchased(result.customerInfo)
    }

    func restore() async throws -> CustomerInfo {
        guard await link() else { throw StoreError.notLinked }
        return try await Purchases.shared.restorePurchases()
    }

    /// Whether RevenueCat is reporting for the linked account right now (its customer info stream
    /// also reports the anonymous user, before log-in and after log-out).
    var reportsLinkedAccount: Bool {
        guard let linkedUserID else { return false }
        return Purchases.shared.appUserID == linkedUserID
    }

    /// How many boosts or super likes a pack holds.
    static func count(of package: Package) -> Int {
        Int(package.storeProduct.productIdentifier.split(separator: ".").last ?? "") ?? 1
    }

    /// drafft tempo's details as the App Store reports them (plan, price, renewal), or nil when it
    /// isn't active. Whether it's on for the account comes from the server (`AppModel.isPremium`).
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
