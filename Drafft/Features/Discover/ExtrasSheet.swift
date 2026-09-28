import SwiftUI
import RevenueCat

/// Boosts, super likes or today's likes: one extra per sheet (boosts from the header, super likes
/// or likes when you run out). The hero shows what the extra does to your place in the deck;
/// below it, packs as a quiet list. One primary action at a time in the pinned footer.
struct ExtrasSheet: View {
    let tab: Tab

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pack: Pack?
    @State private var purchasing = false
    @State private var showPaywall = false
    @State private var lifted = false
    /// Boosts only: the store pushed from the launch page ("Get more boosts").
    @State private var showStore = false
    @State private var receipt: PurchaseReceipt?
    /// Set by the confirmation's "Boost now": launch once it has closed.
    @State private var boostAfterReceipt = false
    /// A purchase that didn't go through, said plainly under the button.
    @State private var failure: String?
    private var store: Store { .shared }

    enum Tab: String, CaseIterable, Identifiable {
        case boost, superLike, likes
        var id: Self { self }
        var title: String {
            switch self {
            case .boost: L("Boosts")
            case .superLike: L("Super likes")
            case .likes: L("Likes")
            }
        }
        var symbol: String {
            switch self {
            case .boost: "bolt.fill"
            case .superLike: "heart.fill"
            case .likes: "heart.text.square.fill"
            }
        }
    }

    /// A pack as the App Store sells it: localized price, and the unit price worked out from it.
    struct Pack: Hashable, Identifiable {
        let count: Int
        let package: Package
        var id: Int { count }
        var price: String { package.storeProduct.localizedPriceString }
        var amount: Decimal { package.storeProduct.price }
        var each: String? {
            guard count > 1 else { return nil }
            let unit = NSDecimalNumber(decimal: amount / Decimal(count))
            return package.storeProduct.priceFormatter?.string(from: unit).map { L("\($0) each") }
        }
    }

    private var packs: [Pack] {
        let source = switch tab {
        case .boost: store.boosts
        case .superLike: store.superLikes
        case .likes: [Package]()
        }
        return source.map { Pack(count: Store.count(of: $0), package: $0) }
    }

    private var isSuper: Bool { tab == .superLike }
    private var blockFill: Color { isSuper ? DS.Palette.negative : DS.Palette.night }
    private var accent: Color { isSuper ? .white : DS.Palette.lime }

    /// Boosts keep buying and launching apart: with boosts in hand (or one running) the sheet
    /// opens on the launch page, whose only action is "Boost now"; the store is a separate page
    /// behind "Get more boosts". With none left, the sheet opens straight on the store, and once
    /// a pack is bought it turns into the launch page.
    private var opensOnLaunch: Bool { tab == .boost && (app.boosts > 0 || app.isBoosting()) }

    var body: some View {
        NavigationStack {
            Group {
                if opensOnLaunch { launchPage } else { storePage(pushed: false) }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showStore) { storePage(pushed: true) }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(purchasing || receipt != nil)
        // Over this sheet: closing it comes back here (boosts: to the launch page).
        // design-lint: allow sheet-surface - PurchaseConfirmation sets its raised surface itself
        .sheet(item: $receipt, onDismiss: afterReceipt) { r in
            receiptView(r)
        }
        .task { await store.load() }
        .onAppear {
            if reduceMotion { lifted = true } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.1)) { lifted = true }
            }
        }
        .sheet(isPresented: $showPaywall) {
            Group {
                PaywallView(onUnlocked: { dismiss() },
                            headline: L("No cap on likes."),
                            pitch: L("Unlimited likes come with drafft tempo, along with a free boost every week."),
                            unlockedTitle: L("Keep swiping"))
            }
            .sheetSurface()
        }
    }

    // MARK: Pages

    /// Use a boost you own. Nothing to buy here.
    private var launchPage: some View {
        ScrollView {
            hero
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.lg)
                .padding(.bottom, DS.Space.xl)
        }
        .scrollIndicators(.hidden)
        .bottomBar {
            VStack(spacing: DS.Space.sm) {
                launchButton
                Button {
                    Haptics.tap()
                    showStore = true
                } label: {
                    Text("Get more boosts")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.md)
            .padding(.bottom, DS.Space.xs)
        }
        .background(DS.Palette.canvasSoft)
    }

    /// Buy a pack. Nothing to launch here. Pushed from the launch page, it skips the hero.
    private func storePage(pushed: Bool) -> some View {
        ScrollView {
            VStack(spacing: DS.Space.md) {
                if !pushed { hero }
                // Packs show once purchases are linked to the account: one bought before that
                // would never be credited.
                if tab != .likes && (packs.isEmpty || !store.isLinked) {
                    packsUnavailable
                } else if !packs.isEmpty {
                    packList(titled: !pushed)
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, pushed ? DS.Space.sm : DS.Space.lg)
            .padding(.bottom, DS.Space.xl)
        }
        .scrollIndicators(.hidden)
        .blurredNavigationEdge()
        .bottomBar { footer }
        .background(DS.Palette.canvasSoft)
        .navigationTitle(pushed ? (tab == .boost ? "Get more boosts" : "Get more super likes") : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(pushed ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if pushed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    /// "Boost now", or disabled with the reason while one runs.
    private var launchButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let running = app.isBoosting(at: context.date)
            Button {
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(Motion.bouncy) { app.startBoost() }
                }
            } label: {
                Label(running ? "Boost running" : "Boost now", systemImage: "bolt.fill")
            }
            .buttonStyle(.drafftPrimary)
            .disabled(running || app.boosts == 0)
        }
    }

    // MARK: Hero

    /// What the extra does, shown literally: your card rising out of the pack to the front.
    private var hero: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(alignment: .top) {
                inventory
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.14), in: .circle)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Close")
            }

            PackFan(lifted: lifted) { badge }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.sm)

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text(headline)
                    .font(.display(40))
                    .displayLeading(40)
                    .foregroundStyle(accent)
                    .accessibilityAddTraits(.isHeader)
                Text(branded: explanation, font: .body, tierColor: isSuper ? .white : DS.Palette.lime)
                    .foregroundStyle(.white.opacity(isSuper ? 0.9 : 0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if tab == .boost { boostStatus }
        }
        .padding(DS.Space.xl)
        .padding(.top, -DS.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Sheet hero: plain fill.
        .background(blockFill, in: .rect(cornerRadius: DS.Radius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .strokeBorder(DS.Palette.blockEdge, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    /// What you have left, as a quiet pill.
    private var inventory: some View {
        HStack(spacing: 6) {
            if isSuper {
                SuperLikeMark(size: 11, color: .white)
            } else {
                Image(systemName: tab.symbol).font(.caption.weight(.heavy))
            }
            Text(inventoryText)
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .rollingDigits(wording: inventoryText.wording)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DS.Space.md)
        .frame(minHeight: 32)
        .background(.white.opacity(0.14), in: .capsule)
        .padding(.top, 6)
    }

    private var inventoryText: String {
        switch tab {
        case .boost: app.boosts == 1 ? L("1 boost left") : L("\(app.boosts) boosts left")
        case .superLike: app.superLikes == 1 ? L("1 super like left") : L("\(app.superLikes) super likes left")
        case .likes: likesText
        }
    }

    private var headline: String {
        switch tab {
        case .boost: L("Lead the pack.")
        case .superLike: L("Stand out.")
        case .likes: app.isPremium ? L("No cap.") : L("Out of likes.")
        }
    }

    private var explanation: String {
        switch tab {
        case .boost: L("For 30 minutes, people nearby see your profile before anyone else's.")
        case .superLike: L("They see you first, with a red heart on your profile. It doesn't use a daily like.")
        case .likes: app.isPremium ? L("drafft tempo has no daily limit.") : L("Your likes refill at midnight, or go unlimited with drafft tempo.")
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch tab {
        case .superLike:
            SuperLikeMark(size: 13, color: .white)
                .offset(x: -3)
                .frame(width: 34, height: 34)
                .background(DS.Palette.negative, in: .circle)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        case .boost, .likes:
            // Likes stay green whatever the brand accent.
            Image(systemName: tab.symbol)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(tab == .likes ? DS.Palette.onLike : DS.Palette.onLime)
                .frame(width: 34, height: 34)
                .background(tab == .likes ? DS.Palette.like : DS.Palette.lime, in: .circle)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        }
    }

    /// While a boost runs: the time left and a draining lane.
    @ViewBuilder
    private var boostStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let end = app.boostEndsAt, app.isBoosting(at: context.date) {
                let left = end.timeIntervalSince(context.date)
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("You're at the front")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(clock(left))
                            .font(.displayBold(22, relativeTo: .title3).monospacedDigit())
                            .foregroundStyle(DS.Palette.lime)
                            .contentTransition(.numericText())
                    }
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.12))
                            .overlay(alignment: .leading) {
                                Capsule().fill(DS.Palette.lime)
                                    .frame(width: geo.size.width * max(0, min(1, left / AppModel.boostDuration)))
                            }
                    }
                    .frame(height: 8)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Packs

    /// Packs as a clean radio list in one white block: count and unit on the left, price and
    /// unit price on the right, hairlines between rows. The picked row tints pale lime.
    private func packList(titled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if titled {
                Text(tab == .boost ? "Get boosts" : "Get more super likes")
                    .font(.headline)
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.horizontal, DS.Space.md)
                    .padding(.top, DS.Space.md)
                    .padding(.bottom, DS.Space.sm)
            }
            ForEach(Array(packs.enumerated()), id: \.element) { i, p in
                if i > 0 {
                    let touchesPick = pack == p || pack == packs[i - 1]
                    Rectangle()
                        .fill(DS.Palette.hairline)
                        .frame(height: 1)
                        .padding(.leading, DS.Space.md + 34)
                        .padding(.trailing, DS.Space.md)
                        .opacity(touchesPick ? 0 : 1)
                }
                packRow(p, best: p == packs.last)
            }
        }
        .padding(DS.Space.xs)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }

    /// Packs still loading, or the App Store couldn't be reached.
    @ViewBuilder
    private var packsUnavailable: some View {
        if store.state == .failed {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Packs couldn't load. Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { Task { await store.load() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentInk)
                    .frame(minHeight: 44)
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
                .accessibilityLabel("Loading packs")
        }
    }

    /// "Save 28%" against the single-unit price of the smallest pack.
    private func saving(_ p: Pack) -> String? {
        guard let first = packs.first, p != first, first.amount > 0 else { return nil }
        let unit = first.amount / Decimal(first.count)
        let full = unit * Decimal(p.count)
        let pct = Int((NSDecimalNumber(decimal: 1 - p.amount / full).doubleValue * 100).rounded())
        return pct > 0 ? L("Save \(pct)%") : nil
    }

    private func packRow(_ p: Pack, best: Bool) -> some View {
        let on = pack == p
        return Button {
            Haptics.select()
            withAnimation(Motion.select) { pack = on ? nil : p }
        } label: {
            HStack(spacing: DS.Space.md) {
                CheckDisc(isOn: on, onLimeFill: true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(p.count)")
                            .font(.displayBold(22, relativeTo: .title3))
                        Text(p.count == 1 ? singular : plural)
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.ink)
                    HStack(spacing: 6) {
                        if let save = saving(p) {
                            Text(save)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.accentInk)
                        }
                        if best {
                            Text("Best value")
                                .font(.caption2.weight(.heavy))
                                // Inverted on the selected (accent) row so the badge never melts into it.
                                .foregroundStyle(on ? DS.Palette.accentInk : DS.Palette.onLime)
                                .padding(.horizontal, 6)
                                .frame(minHeight: 18)
                                .background(on ? AnyShapeStyle(DS.Palette.onLime) : AnyShapeStyle(DS.Palette.lime), in: .capsule)
                        }
                    }
                }

                Spacer(minLength: DS.Space.sm)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(p.price)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.ink)
                    Text(p.each ?? L("Single"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(on ? DS.Palette.onLime.opacity(0.85) : DS.Palette.mute)
                }
            }
            .lineLimit(2)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.md)
            // Selected: solid accent, like every other selection (a pale wash vanished on the sheet's well).
            .background(on ? DS.Palette.lime : .clear, in: .rect(cornerRadius: DS.Radius.lg))
            .contentShape(.rect(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityLabel(best ? L("\(packName(p.count)), \(p.price), best value") : L("\(packName(p.count)), \(p.price)"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var singular: String { tab == .boost ? L("boost") : L("super like") }
    private var plural: String { tab == .boost ? L("boosts") : L("super likes") }

    /// "3 boosts", "1 super like": the count with its unit, as one string.
    private func packName(_ count: Int) -> String {
        if tab == .boost { return count == 1 ? L("1 boost") : L("\(count) boosts") }
        return count == 1 ? L("1 super like") : L("\(count) super likes")
    }

    private func buyTitle(_ p: Pack) -> String {
        if tab == .boost {
            return p.count == 1 ? L("Buy 1 boost for \(p.price)") : L("Buy \(p.count) boosts for \(p.price)")
        }
        return p.count == 1 ? L("Buy 1 super like for \(p.price)") : L("Buy \(p.count) super likes for \(p.price)")
    }

    // MARK: Footer

    /// Store footer: buy the picked pack.
    private var footer: some View {
        VStack(spacing: DS.Space.xs) {
            primaryButton
            Text(failure ?? footnote)
                .font(.caption)
                .foregroundStyle(failure == nil ? DS.Palette.body : DS.Palette.negative)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.md)
        .padding(.bottom, DS.Space.sm)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if tab == .likes {
            if app.isPremium {
                Button("Keep swiping") { dismiss() }.buttonStyle(.drafftPrimary)
            } else {
                Button("Get unlimited likes") { showPaywall = true }.buttonStyle(.drafftPrimary)
            }
        } else {
            Button(action: buy) {
                if purchasing {
                    ProgressView().tint(DS.Palette.onLime)
                        .accessibilityLabel("Adding it to your account")
                } else if let pack {
                    Text(buyTitle(pack))
                } else {
                    Text("Choose a pack")
                }
            }
            .buttonStyle(.drafftPrimary)
            .disabled(pack == nil || purchasing || !store.isLinked)
        }
    }

    private var footnote: String {
        tab == .likes ? L("Unlimited likes come with drafft tempo.") : L("One-time purchase, never expires.")
    }
}

// MARK: Purchase

extension ExtrasSheet {
    private func buy() {
        guard let pack else { return }
        let item: AppModel.Consumable = tab == .boost ? .boost : .superLike
        let before = app.balance(of: item)
        let target: PurchaseCredit.Pending.Target = item == .boost
            ? .boosts(atLeast: before + pack.count)
            : .superLikes(atLeast: before + pack.count)
        Haptics.tap()
        purchasing = true
        failure = nil
        Task {
            defer { purchasing = false }
            let transactionID: String?
            do {
                guard case .purchased(_, let id) = try await store.purchase(pack.package) else { return }
                transactionID = id
            } catch {
                Haptics.warning()
                failure = L("The purchase didn't go through. You haven't been charged.")
                return
            }
            // Confirmed by the App Store: the server is asked to credit the pack at once. Slow, the
            // button frees and a banner at the top takes over. The count shown is always the
            // wallet's, never one made up on the device.
            let purchase = PurchaseCredit.Pending(transactionID: transactionID,
                                                  productID: pack.package.storeProduct.productIdentifier,
                                                  date: .now, target: target)
            guard await PurchaseCredit.shared.confirmed(purchase, app: app) else { return }
            withAnimation(Motion.bouncy) { self.pack = nil }
            // Boosts: back to the launch page, now showing the new count.
            if showStore { showStore = false }
            receipt = PurchaseReceipt(item: tab == .boost
                ? .boosts(count: pack.count, price: pack.price, balance: app.boosts)
                : .superLikes(count: pack.count, price: pack.price, balance: app.superLikes))
        }
    }

    @ViewBuilder
    private func receiptView(_ r: PurchaseReceipt) -> some View {
        if tab == .boost && !app.isBoosting() {
            PurchaseConfirmation(receipt: r, primaryTitle: L("Boost now"), primary: {
                boostAfterReceipt = true
                receipt = nil
            }, secondaryTitle: L("Later")) { receipt = nil }
        } else if tab == .boost {
            PurchaseConfirmation(receipt: r, primaryTitle: L("Got it")) { receipt = nil }
        } else {
            PurchaseConfirmation(receipt: r, primaryTitle: L("Got it")) { receipt = nil }
        }
    }

    /// Super likes: back to the deck. Boosts: stay on the launch page, or launch right away.
    private func afterReceipt() {
        if tab == .superLike { dismiss(); return }
        guard boostAfterReceipt else { return }
        boostAfterReceipt = false
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(Motion.bouncy) { app.startBoost() }
        }
    }
}

/// Three dimmed athletes (`PackPhotos`, the pile you stand out from, so your own gender), fanned;
/// yours lifts out in front with the extra's badge.
private struct PackFan<Badge: View>: View {
    let lifted: Bool
    @ViewBuilder var badge: Badge

    @Environment(AppModel.self) private var app
    /// Picked once per opening.
    @State private var others: [String] = []

    var body: some View {
        let angles: [Double] = [-14, 0, 14]
        let xs: [CGFloat] = [-78, 0, 78]
        ZStack {
            ForEach(Array(others.enumerated()), id: \.offset) { i, portrait in
                Photo(name: portrait, side: 84)
                    .frame(width: 84, height: 112)
                    .clipShape(.rect(cornerRadius: DS.Radius.lg))
                    .saturation(0)
                    .opacity(0.4)
                    .rotationEffect(.degrees(angles[i]), anchor: .bottom)
                    .offset(x: xs[i], y: i == 1 ? -6 : 8)
            }
            Photo(name: app.me.portrait, side: 108)
                .frame(width: 108, height: 144)
                .clipShape(.rect(cornerRadius: DS.Radius.lg))
                // The badge sits inside the card's corner: nothing hangs off a block.
                .overlay(alignment: .topTrailing) {
                    badge.padding(DS.Space.sm)
                }
                .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
                .scaleEffect(lifted ? 1 : 0.82)
                .offset(y: lifted ? -4 : 30)
                .rotationEffect(.degrees(lifted ? -3 : 0))
        }
        .frame(height: 170)
        .accessibilityHidden(true)
        .onAppear { if others.isEmpty { others = PackPhotos.pick(for: DiscoverFilters.audience(of: app.me)) } }
    }
}

extension ExtrasSheet {
    /// Likes left today as the server counts them; the daily allowance until it's read.
    fileprivate var likesText: String {
        if app.isPremium { return L("Unlimited likes") }
        guard let left = app.likesLeft else { return L("\(AppModel.dailyLikes) likes a day") }
        return L("\(left) of \(AppModel.dailyLikes) likes left")
    }
}
