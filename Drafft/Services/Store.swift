import Foundation
import os
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
    private static let log = AppLog("store")

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
            Telemetry.unexpected(error, "purchase", "link")
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
                // The screen went away: nothing failed, the next load starts afresh.
                guard Telemetry.kind(of: error) != .cancelled else { state = .idle; return }
                state = .failed
                Telemetry.track(.productsLoadFailed)
                Telemetry.unexpected(error, "purchase", "load_offerings")
                return
            }
        }
        let empty = tempo.isEmpty && boosts.isEmpty && superLikes.isEmpty
        state = linked && !empty ? .loaded : .failed
    }

    /// Confirmed by the App Store, with its transaction (the reference support asks for).
    enum Outcome { case purchased(CustomerInfo, transactionID: String?), cancelled }

    /// Only for the linked account. What was bought shows once the server has credited it (the
    /// wallet), never from here.
    func purchase(_ package: Package) async throws -> Outcome {
        let productID = package.storeProduct.productIdentifier
        let kind = AnalyticsEvent.ProductKind(productID: productID)
        Telemetry.track(.purchaseStarted(kind, productID: productID))
        let outcome: Outcome
        do {
            outcome = try await purchaseLinked(package)
        } catch {
            if let problem = PurchaseProblem(purchaseError: error) {
                Telemetry.track(.purchaseFailed(kind, productID: productID, problem: problem.code))
            } else if (error as? RevenueCat.ErrorCode) == .purchaseCancelledError {
                // RevenueCat reports the person's cancel as an error too.
                Telemetry.track(.purchaseCancelled(kind, productID: productID))
            } else if !(error is CancellationError) {
                Telemetry.track(.purchaseFailed(kind, productID: productID, problem: "unknown"))
            }
            // A purchase that failed in a way nothing else explains may have been charged: reported as such.
            let unconfirmed = PurchaseProblem(purchaseError: error) == .unconfirmed && Telemetry.kind(of: error) == .unexpected
            Telemetry.unexpected(error, "purchase", "purchase", extra: ["product_id": productID],
                                 kind: unconfirmed ? .storeUnconfirmed : nil)
            throw error
        }
        switch outcome {
        case .purchased:
            Telemetry.track(.purchaseCompleted(kind, productID: productID, currency: package.storeProduct.currencyCode))
        case .cancelled:
            Telemetry.track(.purchaseCancelled(kind, productID: productID))
        }
        return outcome
    }

    private func purchaseLinked(_ package: Package) async throws -> Outcome {
        guard await link() else { throw StoreError.notLinked }
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled { return .cancelled }
        return .purchased(result.customerInfo, transactionID: result.transaction?.transactionIdentifier)
    }

    /// Why a purchase didn't complete, in words that stay true whatever the App Store did. Nil: the
    /// person cancelled (nothing to say). Only the purchase path builds one (`init?(purchaseError:)`):
    /// `link`, `load_offerings` and `restore` errors are reported as they are (`Telemetry.unexpected`:
    /// RevenueCat unreachable is offline, a breadcrumb; anything else is an issue).
    enum PurchaseProblem: Equatable {
        /// Waiting for a parent's approval (Ask to Buy) or the bank's: RevenueCat gets the purchase
        /// once it goes through, and the server credits it then.
        case pending
        /// Screen Time or a profile forbids purchases on this iPhone.
        case notAllowed
        /// The subscription is already on this Apple ID: Restore brings it to this account.
        case alreadyOwned
        /// Refused before the App Store took any payment.
        case notCharged
        /// Not confirmed, and the App Store may have charged: RevenueCat keeps the transaction and
        /// sends it again (next launch, back to the app), and the server credits it then.
        case unconfirmed
        /// The account couldn't be linked (offline): nothing was asked of the App Store.
        case notLinked

        /// A purchase's failure. Nil: the person cancelled, or the task went away (nothing to say).
        /// Only for the purchase path: a code the store gave that isn't known here is `unconfirmed`
        /// (the App Store may have charged), which doesn't hold for loading offerings or restoring.
        init?(purchaseError error: Error) {
            if case StoreError.notLinked = error { self = .notLinked; return }
            // The task was cancelled (the screen went away): not a purchase that failed.
            if error is CancellationError { return nil }
            guard let code = error as? RevenueCat.ErrorCode else { self = .unconfirmed; return }
            if code == .purchaseCancelledError { return nil }
            self = Self(code: code) ?? .unconfirmed
        }

        /// What RevenueCat's own code says the store did, when it says: nil for the codes that don't
        /// tell (and for the cancel).
        init?(code: RevenueCat.ErrorCode) {
            switch code {
            case .paymentPendingError: self = .pending
            case .purchaseNotAllowedError: self = .notAllowed
            case .productAlreadyPurchasedError: self = .alreadyOwned
            case .purchaseInvalidError, .productNotAvailableForPurchaseError, .ineligibleError,
                 .invalidPromotionalOfferError, .operationAlreadyInProgressForProductError:
                self = .notCharged
            default: return nil
            }
        }

        /// `restorable`: the screen has Restore purchases.
        func message(restorable: Bool) -> String {
            switch self {
            case .pending: L("Waiting for approval. It'll be added to your account once the payment goes through.")
            case .notAllowed: L("Purchases are turned off on this iPhone. You can allow them in Screen Time settings.")
            case .alreadyOwned where restorable: L("This is already on your Apple ID. Tap Restore purchases to get it back.")
            case .notCharged: L("The purchase didn't go through. You haven't been charged.")
            case .alreadyOwned, .unconfirmed:
                L("We couldn't confirm the purchase. If you were charged, it'll be added to your account automatically.")
            case .notLinked: L("Couldn't connect. Check your connection and try again.")
            }
        }

        /// The problem as an analytics code (`not_allowed`).
        var code: String {
            switch self {
            case .pending: "pending"
            case .notAllowed: "not_allowed"
            case .alreadyOwned: "already_owned"
            case .notCharged: "not_charged"
            case .unconfirmed: "unconfirmed"
            case .notLinked: "not_linked"
            }
        }
    }

    func restore() async throws -> CustomerInfo {
        do {
            guard await link() else { throw StoreError.notLinked }
            let info = try await Purchases.shared.restorePurchases()
            Telemetry.track(.purchasesRestored(found: info.entitlements[Self.tempoEntitlement]?.isActive == true))
            return info
        } catch {
            if Telemetry.kind(of: error) != .cancelled {
                Telemetry.track(.restoreFailed)
                Telemetry.unexpected(error, "purchase", "restore")
            }
            throw error
        }
    }

    /// Whether RevenueCat is reporting for the linked account right now (its customer info stream
    /// also reports the anonymous user, before log-in and after log-out).
    var reportsLinkedAccount: Bool {
        guard let linkedUserID else { return false }
        return Purchases.shared.appUserID == linkedUserID
    }

    /// The linked account's purchases as the App Store says them now, past RevenueCat's cache:
    /// turning renewal off in Apple's sheet makes no transaction, so the stream (DrafftApp) may not
    /// report it for a while. Nil when RevenueCat isn't reporting for the linked account or the read
    /// failed, both logged.
    func currentCustomerInfo() async -> CustomerInfo? {
        guard reportsLinkedAccount else {
            Self.log.notice("Subscription refresh skipped: RevenueCat isn't reporting for the linked account")
            return nil
        }
        do {
            return try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
        } catch {
            Self.log.error("Subscription refresh failed: \(error.localizedDescription)")
            return nil
        }
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
