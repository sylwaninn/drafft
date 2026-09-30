import SwiftUI
import StoreKit
import RevenueCat

/// drafft tempo paywall. Plans and prices come from the App Store through RevenueCat (`Store`).
struct PaywallView: View {
    /// Called after a successful purchase, e.g. to perform the undo that opened the paywall.
    var onUnlocked: () -> Void = {}
    var headline = L("Take it back.")
    var pitch = L("Undo is part of drafft tempo, along with a few things that get you to a first session faster.")
    /// The next step offered once subscribed (on the purchase confirmation).
    var unlockedTitle = L("Continue")

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Nothing chosen on arrival: the person picks a plan.
    @State private var plan: Plan?
    @State private var purchasing = false
    @State private var restoring = false
    /// Outcome of a purchase or restore that didn't unlock anything, said plainly.
    @State private var notice: String?
    @State private var receipt: PurchaseReceipt?
    private var store: Store { .shared }

    enum Plan: CaseIterable, Identifiable {
        case month, sixMonths, year
        var id: Self { self }
        var title: String {
            switch self {
            case .month: L("1 month")
            case .sixMonths: L("6 months")
            case .year: L("12 months")
            }
        }
        var months: Int {
            switch self {
            case .month: 1
            case .sixMonths: 6
            case .year: 12
            }
        }

        /// From an App Store product ID: `so.drafft.app.tempo.monthly`, `.sixmonths`, `.yearly`.
        init?(productID: String) {
            switch productID.split(separator: ".").last {
            case "monthly": self = .month
            case "sixmonths": self = .sixMonths
            case "yearly": self = .year
            default: return nil
            }
        }

        /// How the plan is billed, with the App Store's localized price.
        func total(_ price: String) -> String {
            switch self {
            case .month: L("\(price) billed monthly")
            case .sixMonths: L("\(price) every 6 months")
            case .year: L("\(price) billed yearly")
            }
        }

        /// How the active plan reads in You › drafft tempo.
        func billing(_ price: String) -> String {
            switch self {
            case .month: L("\(price) a month")
            case .sixMonths: L("\(price) every 6 months")
            case .year: L("\(price) a year")
            }
        }
    }

    /// "Most popular" on 6 months; on 12 months, the saving against paying monthly.
    private func tag(_ p: Plan) -> String? {
        switch p {
        case .month: return nil
        case .sixMonths: return L("Most popular")
        case .year:
            guard let monthly = store.tempo[.month]?.storeProduct.price,
                  let perMonth = store.tempo[.year]?.storeProduct.pricePerMonth?.decimalValue,
                  monthly > 0 else { return nil }
            let pct = Int((NSDecimalNumber(decimal: 1 - perMonth / monthly).doubleValue * 100).rounded())
            return pct > 0 ? L("Save \(pct)%") : nil
        }
    }

    private var perks: [(icon: String, title: String, detail: String)] { [
        ("arrow.uturn.backward", L("Undo any swipe"), L("Swiped too fast? Bring them back.")),
        ("heart.text.square", L("See who liked you"), L("Match instantly with people already into you.")),
        ("infinity", L("Unlimited likes"), L("No daily cap, like everyone you'd train with.")),
        ("bolt.fill", L("Weekly boost"), L("One free boost every week: 30 minutes at the top of decks near you."))
    ] }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DS.Palette.night.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xxl) {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        // The tier lockup: the wordmark, then "tempo" in the same face and size,
                        // lowercase, in the accent.
                        HStack(alignment: .lastTextBaseline, spacing: 26 * 0.28) {
                            Wordmark(size: 26, color: .white, trail: DS.Palette.accentOnNight.opacity(0.5))
                            Text(verbatim: Brand.tier)
                                .font(.display(26))
                                .tracking(-26 * 0.02)
                                .foregroundStyle(DS.Palette.accentOnNight)
                                .fixedSize()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Brand.tierName)
                        Text(headline)
                            .font(.display(52))
                            .displayLeading(52)
                            .foregroundStyle(DS.Palette.accentOnNight)
                            .accessibilityAddTraits(.isHeader)
                        Text(branded: pitch, font: .body, tierColor: DS.Palette.accentOnNight)
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        ForEach(perks, id: \.title) { perk in
                            HStack(alignment: .top, spacing: DS.Space.md) {
                                Image(systemName: perk.icon)
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(DS.Palette.onAccentOnNight)
                                    .frame(width: 40, height: 40)
                                    .background(DS.Palette.accentOnNight, in: .circle)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(perk.title).font(.headline).foregroundStyle(.white)
                                    Text(perk.detail).font(.subheadline).foregroundStyle(.white.opacity(0.65))
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }

                    plans
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.xxxl)
                .padding(.bottom, DS.Space.xl)
            }
            .scrollIndicators(.hidden)
            .bottomBar { footer }
            .nightSurface()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.14), in: .circle)
            }
            .padding(DS.Space.lg)
            .accessibilityLabel("Not now")
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(purchasing || receipt != nil)
        .task { await store.load() }
        // Over the paywall; closing it closes both, then the unlocked action runs.
        // design-lint: allow sheet-surface - PurchaseConfirmation sets its raised surface itself
        .sheet(item: $receipt, onDismiss: {
            dismiss()
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                onUnlocked()
            }
        }) { r in
            PurchaseConfirmation(receipt: r, primaryTitle: unlockedTitle) { receipt = nil }
        }
    }

    /// The plans the App Store returned, or why there are none yet. They show once purchases are
    /// linked to the account too: a plan bought before that would never be credited.
    @ViewBuilder
    private var plans: some View {
        let available = Plan.allCases.compactMap { p in store.tempo[p].map { (p, $0) } }
        if !available.isEmpty && store.isLinked {
            VStack(spacing: DS.Space.sm) {
                ForEach(available, id: \.0) { p, package in planRow(p, package) }
            }
        } else if store.state == .failed {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("Plans couldn't load. Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { Task { await store.load() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentOnNight)
                    .frame(minHeight: 44)
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: .rect(cornerRadius: DS.Radius.xl))
        } else {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityLabel("Loading plans")
        }
    }

    private func planRow(_ p: Plan, _ package: Package) -> some View {
        let on = plan == p
        let product = package.storeProduct
        return Button {
            Haptics.select()
            withAnimation(Motion.select) { plan = p }
        } label: {
            HStack(spacing: DS.Space.md) {
                CheckDisc(isOn: on, ring: .white.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    // The tag sits after the title, on the same line; it only drops under it at the largest text sizes.
                    let tagView = tag(p).map { tag in
                        Text(tag)
                            .font(.caption2.weight(.bold))
                            .fixedSize()
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(DS.Palette.onAccentOnNight)
                            .background(DS.Palette.accentOnNight, in: .capsule)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: DS.Space.sm) {
                            Text(p.title).font(.headline).foregroundStyle(.white).fixedSize()
                            tagView
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.title).font(.headline).foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            tagView
                        }
                    }
                    Text(p.total(product.localizedPriceString)).font(.footnote).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: DS.Space.sm)
                // "7,33 €/month" on one line; stacked only when it can't fit.
                let perMonth = product.localizedPricePerMonth ?? product.localizedPriceString
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(perMonth).font(.displayBold(20, relativeTo: .title3)).foregroundStyle(.white)
                        Text("/ month").font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                    .fixedSize()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(perMonth).font(.displayBold(20, relativeTo: .title3)).foregroundStyle(.white)
                        Text("/ month").font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                    .fixedSize()
                }
            }
            .padding(DS.Space.lg)
            .background(on ? DS.Palette.selectedOnNight : .white.opacity(0.07), in: .rect(cornerRadius: DS.Radius.xl))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: DS.Space.xs) {
            Button(action: purchase) {
                if purchasing {
                    ProgressView().tint(DS.Palette.onAccentOnNight)
                        .accessibilityLabel("Adding it to your account")
                } else {
                    Text(branded: L("Get drafft tempo"), font: .body.weight(.semibold), brandWeight: .heavy,
                         tierColor: DS.Palette.night)
                }
            }
            .buttonStyle(.drafftPrimary)
            .disabled(plan == nil || purchasing || !store.isLinked)

            // Why it's disabled, only while it is: no empty line under the button once a plan
            // is picked.
            if plan == nil {
                Text("Pick a plan to continue.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, DS.Space.xs)
                    .transition(.opacity)
            }

            // One row while it fits; otherwise restore on its own line above the two documents.
            let restoreLink = Button(action: restore) {
                Text("Restore purchases")
                    .opacity(restoring ? 0 : 1)
                    .overlay { if restoring { ProgressView().tint(.white) } }
                    .frame(minHeight: 44).contentShape(.rect)
            }
            .disabled(restoring || purchasing || !store.isLinked)
            .accessibilityLabel(restoring ? "Restoring purchases" : "Restore purchases")
            let termsLink = Button { openURL(LegalDoc.terms.url(), prefersInApp: true) } label: {
                Text("Terms").frame(minHeight: 44).contentShape(.rect)
            }
            .accessibilityLabel(LegalDoc.terms.title)
            let privacyLink = Button { openURL(LegalDoc.privacy.url(), prefersInApp: true) } label: {
                Text("Privacy").frame(minHeight: 44).contentShape(.rect)
            }
            .accessibilityLabel(LegalDoc.privacy.title)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.lg) { restoreLink; termsLink; privacyLink }.fixedSize()
                VStack(spacing: 0) {
                    restoreLink
                    HStack(spacing: DS.Space.lg) { termsLink; privacyLink }
                }
                .fixedSize()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))

            if let notice {
                Label(notice, systemImage: "info.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            // 0.6 at least: 0.45 white on night fell under 4.5:1.
            // App Store terms for auto-renewable subscriptions.
            Text("Payment is charged to your Apple Account. The subscription renews automatically at the same price unless you cancel it at least 24 hours before the end of the period. Manage or cancel it in your App Store settings.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.md)
        .padding(.bottom, DS.Space.sm)
    }

    private func say(_ text: String) {
        withAnimation(Motion.snappy) { notice = text }
    }

    /// Restores from the App Store, for the signed-in account. Unlocks once the server has drafft
    /// tempo on the account's wallet.
    private func restore() {
        Haptics.tap()
        restoring = true
        notice = nil
        Task {
            defer { restoring = false }
            do {
                let info = try await store.restore()
                if let sub = store.subscription(from: info) {
                    app.subscription = sub
                    let product = info.entitlements[Store.tempoEntitlement]?.productIdentifier ?? Store.tempoEntitlement
                    let restored = PurchaseCredit.Pending(transactionID: nil, productID: product, date: .now, target: .tempo)
                    guard await PurchaseCredit.shared.confirmed(restored, app: app) else { return }
                    Haptics.success()
                    receipt = PurchaseReceipt(item: .tempo(sub))
                } else {
                    Haptics.warning()
                    say(L("No drafft tempo purchase on this Apple ID."))
                }
            } catch {
                Haptics.warning()
                say(L("Couldn't reach the App Store. Try again."))
            }
        }
    }

    private func purchase() {
        guard let plan, let package = store.tempo[plan] else { return }
        Haptics.tap()
        purchasing = true
        notice = nil
        Task {
            defer { purchasing = false }
            do {
                switch try await store.purchase(package) {
                case .cancelled:
                    break
                case .purchased(let info, let transactionID):
                    // Confirmed by the App Store: the server is asked to turn drafft tempo on at once
                    // (it also credits the first weekly boost); slow, a banner at the top takes over.
                    // Nothing is unlocked on the device's word alone.
                    let price = package.storeProduct.localizedPriceString
                    let sub = store.subscription(from: info) ?? TempoSubscription(plan: plan, billing: plan.billing(price))
                    app.subscription = sub
                    let purchase = PurchaseCredit.Pending(transactionID: transactionID,
                                                          productID: package.storeProduct.productIdentifier,
                                                          date: .now, target: .tempo)
                    guard await PurchaseCredit.shared.confirmed(purchase, app: app) else { return }
                    receipt = PurchaseReceipt(item: .tempo(sub))
                }
            } catch {
                Haptics.warning()
                say(L("The purchase didn't go through. You haven't been charged."))
            }
        }
    }
}

// MARK: - Subscription (You › drafft tempo)

/// The active subscription, as the App Store reports it. Plan, price, next renewal (or end date
/// once cancelled), what's included, and the way to change or cancel it: Apple's own
/// subscription sheet, since billing belongs to the App Store.
struct SubscriptionSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var managing = false
    @State private var restoring = false
    @State private var restoreResult: String?

    private var perks: [(icon: String, title: String)] { [
        ("arrow.uturn.backward", L("Undo any swipe")),
        ("heart.text.square", L("See who liked you")),
        ("infinity", L("Unlimited likes")),
        ("bolt.fill", L("One free boost every week"))
    ] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.md) {
                    if let sub = app.subscription {
                        status(sub)
                        included
                        billing(sub)
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.sm)
                .padding(.bottom, DS.Space.xl)
            }
            .background(DS.Palette.canvasSoft)
            .navigationTitle("drafft tempo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .blurredNavigationEdge()
            .bottomBar { footer }
            .manageSubscriptionsSheet(isPresented: $managing)
            // Back from Apple's sheet: read what the App Store now says (cancelled, plan change).
            .onChange(of: managing) { _, open in if !open { Task { await refresh() } } }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Blocks

    private func status(_ sub: TempoSubscription) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 22 * 0.28) {
                    Wordmark(size: 22, color: .white, trail: DS.Palette.accentOnNight.opacity(0.5))
                    Text(verbatim: Brand.tier)
                        .font(.display(22))
                        .tracking(-22 * 0.02)
                        .foregroundStyle(DS.Palette.accentOnNight)
                        .fixedSize()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Brand.tierName)
                Spacer(minLength: DS.Space.sm)
                Text(sub.willRenew ? "Active" : "Ending")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(sub.willRenew ? DS.Palette.onAccentOnNight : DS.Palette.night)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 24)
                    .background(sub.willRenew ? DS.Palette.accentOnNight : .white, in: .capsule)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(sub.billing)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(sub.willRenew
                     ? "Renews on \(sub.periodEnds.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(.app)))"
                     : "Cancelled. You keep everything until \(sub.periodEnds.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(.app))).")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Sheet block: plain night.
        .background(DS.Palette.night, in: .rect(cornerRadius: DS.Radius.xl))
        .nightSurface()
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .strokeBorder(DS.Palette.blockEdge, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(Motion.snappy, value: sub.willRenew)
    }

    private var included: some View {
        SheetBlock(title: L("Included")) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                ForEach(perks, id: \.title) { perk in
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: perk.icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(DS.Palette.ink)
                            .frame(width: 32, height: 32)
                            .background(DS.Palette.canvasSoft, in: .circle)
                        Text(perk.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func billing(_ sub: TempoSubscription) -> some View {
        SheetBlock(title: L("Billing")) {
            Text(branded: L("Your subscription is billed through your Apple Account and renews automatically unless you cancel it at least 24 hours before the end of the current period. To change your plan or cancel, go to your App Store subscriptions. Deleting drafft doesn't cancel it."),
                 font: .subheadline)
                .foregroundStyle(DS.Palette.body)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
            } label: {
                Label("Open App Store subscriptions", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentInk)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // One row while it fits; otherwise restore on its own line above the two documents.
            let restoreLink = Button(action: restore) {
                Text("Restore purchases")
                    .opacity(restoring ? 0 : 1)
                    .overlay { if restoring { ProgressView().tint(DS.Palette.ink) } }
                    .frame(minHeight: 44).contentShape(.rect)
            }
            .disabled(restoring)
            .accessibilityLabel(restoring ? "Restoring purchases" : "Restore purchases")
            let termsLink = Button("Terms") { openURL(LegalDoc.terms.url(), prefersInApp: true) }
                .frame(minHeight: 44)
                .accessibilityLabel(LegalDoc.terms.title)
            let privacyLink = Button("Privacy") { openURL(LegalDoc.privacy.url(), prefersInApp: true) }
                .frame(minHeight: 44)
                .accessibilityLabel(LegalDoc.privacy.title)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.lg) { restoreLink; termsLink; privacyLink }.fixedSize()
                VStack(spacing: 0) {
                    restoreLink
                    HStack(spacing: DS.Space.lg) { termsLink; privacyLink }
                }
                .fixedSize()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(DS.Palette.body)
            if let restoreResult {
                Label(restoreResult, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.positiveDeep)
                    .transition(.opacity)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: DS.Space.sm) {
            Button {
                Haptics.tap()
                managing = true
            } label: {
                Text("Manage subscription")
            }
            .buttonStyle(.drafftDark)
            Text("Change plan or cancel in Apple's subscription settings.")
                .font(.footnote)
                .foregroundStyle(DS.Palette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.md)
    }

    // MARK: Actions

    private func restore() {
        Haptics.tap()
        restoring = true
        Task {
            defer { restoring = false }
            do {
                let info = try await Store.shared.restore()
                apply(info)
                await app.loadWallet()
                Haptics.success()
                withAnimation(Motion.snappy) { restoreResult = L("Your subscription is up to date.") }
            } catch {
                Haptics.warning()
                withAnimation(Motion.snappy) { restoreResult = L("Couldn't reach the App Store. Try again.") }
            }
        }
    }

    private func refresh() async {
        if Store.shared.reportsLinkedAccount, let info = try? await Purchases.shared.customerInfo() { apply(info) }
        await app.loadWallet()
    }

    /// What the App Store reports. Expired closes the page, since the drafft tempo row only
    /// shows while subscribed.
    private func apply(_ info: CustomerInfo) {
        let sub = Store.shared.subscription(from: info)
        if sub == nil {
            dismiss()
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation(Motion.snappy) { app.subscription = nil }
            }
        } else {
            withAnimation(Motion.snappy) { app.subscription = sub }
        }
    }
}
