import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var app
    @State private var drag: CGSize = .zero
    @State private var flying: FlyOut?
    @State private var detail: Profile?
    @State private var likeBurst = 0
    @State private var passBurst = 0
    @State private var showPaywall = false
    @State private var showFilters = false
    @State private var extras: ExtrasSheet.Tab?
    @State private var superBurst = 0
    @State private var showLikes = false
    @State private var showLikesPaywall = false
    /// Waiting for confirmation before spending a super like.
    @State private var superLikeTarget: Profile?

    struct FlyOut: Equatable { let id: String; let liked: Bool; var superLike = false; var dy: CGFloat = 0 }

    private let threshold: CGFloat = 110
    /// Likes moved to their own tab (test). The header chip is kept for that variant; flip to bring it back.
    private static let likesInHeader = false

    /// -1…1: how far the top card is committed toward pass (−) or like (+).
    private var progress: CGFloat { max(-1, min(1, drag.width / threshold)) }

    var body: some View {
        NavigationStack {
            // Header, deck and buttons share one stack so a dragged card can pass over the header
            // (it sits below the deck) but never over the like/pass buttons (above it).
            VStack(spacing: 0) {
                topBar
                    .zIndex(0)
                if app.deck.isEmpty {
                    emptyState
                        .padding(.bottom, DS.Space.xl)
                } else {
                    deck
                        .zIndex(1)
                    // Same space above and below: centred between the cards and the tab bar.
                    actions
                        .padding(.vertical, DS.Space.lg)
                        .zIndex(2)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .background(DS.Palette.canvasSoft)
            .ignoresSafeArea(.keyboard) // the deck keeps its size, keyboard or not
            .sheet(isPresented: $showFilters) { Group { FiltersSheet(filters: app.filters) }.sheetSurface() }
            .sheet(isPresented: $showLikes) { Group { LikesYouView() }.sheetSurface() }
            .sheet(isPresented: $showLikesPaywall) {
                Group {
                    PaywallView(onUnlocked: { showLikes = true },
                                headline: L("See who likes you."),
                                pitch: L("drafft tempo shows everyone who already liked you, so you can match in one tap."),
                                unlockedTitle: L("See who likes you"))
                }
                .sheetSurface()
            }
            .sheet(item: $extras) { t in Group { ExtrasSheet(tab: t) }.sheetSurface() }
            .sheet(isPresented: $showPaywall) {
                Group {
                    PaywallView(onUnlocked: { withAnimation(Motion.bouncy) { app.undo() } },
                                unlockedTitle: L("Undo my last swipe"))
                }
                .sheetSurface()
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            // Full-screen cover (no system slide; the composer fades itself) so it sits above the
            // tab bar without hiding it: hiding the tab bar would resize the deck behind.
            .fullScreenCover(item: $superLikeTarget) { p in
                SuperLikeComposer(profile: p, left: app.superLikes) { note in
                    withoutAnimation { superLikeTarget = nil }
                    commit(p, liked: true, superLike: true, opener: note.isEmpty ? nil : .text(note))
                } onCancel: {
                    withoutAnimation { superLikeTarget = nil }
                }
                .presentationBackground(.clear)
            }
            .onAppear {
                // Demo shortcut for screenshots: -profile <id>
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-profile"), i + 1 < args.count { detail = MockData.profile(args[i + 1]) }
            }
            .sheet(item: $detail) { p in
                Group {
                    NavigationStack {
                        ProfileDetailView(profile: p, mode: .discover) { liked, opener in
                            detail = nil
                            commit(p, liked: liked, opener: opener)
                        } onSuperLike: { opener in
                            detail = nil
                            commit(p, liked: true, superLike: true, opener: opener)
                        }
                    }
                }
                .sheetSurface()
            }
        }
    }

    // MARK: Deck

    /// How far back a card sits in the stack (0 = in play). While the top card flies out, every card
    /// behind moves up one step, and the one right behind also follows the drag, so the stack
    /// glides forward instead of snapping once the top card is gone.
    private func depth(_ i: Int) -> CGFloat {
        if i == 0 { return 0 }
        let promoted: CGFloat = flying != nil ? 1 : 0
        let follow: CGFloat = (i == 1 && flying == nil) ? abs(progress) * 0.5 : 0
        return max(0, CGFloat(i) - promoted - follow)
    }

    private var deck: some View {
        GeometryReader { geo in
            ZStack {
                // One extra card is kept hidden at the back so it can fade in when the stack moves up.
                ForEach(Array(app.deck.prefix(4).enumerated().reversed()), id: \.element.id) { i, p in
                    let isTop = i == 0
                    let d = depth(i)
                    // A card flying out keeps its LIKE/PASS stamp fully shown.
                    let stamp: CGFloat = flying?.id == p.id ? (flying?.liked == true ? 1 : -1) : progress
                    SwipeCard(profile: p, me: app.me, progress: isTop ? stamp : 0, isTop: isTop) {
                        detail = p
                    }
                    .frame(width: geo.size.width, height: geo.size.height - 28)
                    // Cards behind are veiled in sage so the top card reads as the one in play.
                    .overlay { DeckVeil(amount: isTop ? 0 : veilAmount(d)) }
                    .shadow(color: .black.opacity(isTop ? 0.22 : Double(max(0, 1 - d)) * 0.22), radius: 20, y: 12)
                    .scaleEffect(1 - d * 0.07, anchor: .bottom)
                    .offset(y: d * 14)
                    .opacity(d > 2.5 ? 0 : 1)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(isTop ? topOffset(p, width: geo.size.width) : .zero)
                    .rotationEffect(.degrees(isTop ? topRotation(p) : 0), anchor: .bottom)
                    .gesture(isTop ? swipe(p) : nil)
                    .allowsHitTesting(isTop)
                    .zIndex(isTop ? 10 : Double(4 - i))
                    .accessibilityHidden(!isTop)
                    .accessibilityActions {
                        Button("Like") { commit(p, liked: true) }
                        Button("Super like") { askSuperLike(p) }
                        Button("Pass") { commit(p, liked: false) }
                        Button("Open profile") { detail = p }
                    }
                    // Undo brings a card back on top with a soft scale-in.
                    .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .identity))
                }
            }
        }
    }

    private func veilAmount(_ d: CGFloat) -> Double {
        Double(min(d, 1)) * 0.55 + Double(max(0, d - 1)) * 0.2
    }

    private func topOffset(_ p: Profile, width: CGFloat) -> CGSize {
        if let flying, flying.id == p.id {
            if flying.superLike { return CGSize(width: 0, height: -width * 2.2) }
            return CGSize(width: (flying.liked ? 1 : -1) * width * 1.6, height: flying.dy + 40)
        }
        return drag
    }

    private func topRotation(_ p: Profile) -> Double {
        if let flying, flying.id == p.id { return flying.superLike ? 0 : (flying.liked ? 18 : -18) }
        return Double(drag.width / 18)
    }

    private func swipe(_ p: Profile) -> some Gesture {
        DragGesture()
            .onChanged { v in
                let crossedBefore = abs(drag.width) >= threshold
                drag = v.translation
                if crossedBefore != (abs(drag.width) >= threshold) { Haptics.select() }
            }
            .onEnded { v in
                let predicted = v.predictedEndTranslation.width
                if abs(v.translation.width) > threshold || abs(predicted) > threshold * 2.4 {
                    commit(p, liked: (abs(predicted) > abs(v.translation.width) ? predicted : v.translation.width) > 0)
                } else {
                    withAnimation(Motion.bouncy) { drag = .zero }
                }
            }
    }

    private func commit(_ p: Profile, liked: Bool, superLike: Bool = false, opener: MessageContent? = nil) {
        guard flying == nil else { return }
        // Out of likes or super likes: the card springs back and the extras sheet explains why.
        if superLike && app.superLikes == 0 || liked && !superLike && !app.canLike {
            Haptics.warning()
            withAnimation(Motion.bouncy) { drag = .zero }
            extras = superLike ? .superLike : .likes
            return
        }
        liked ? Haptics.thump() : Haptics.tap()
        if superLike { superBurst += 1 } else if liked { likeBurst += 1 } else { passBurst += 1 }
        // One smooth spring moves everything at once: the top card flies out while the
        // stack behind glides forward into place.
        withAnimation(.smooth(duration: 0.26, extraBounce: 0.04)) {
            // The drag is released in the same animation, so the buttons ease back to rest
            // while the card flies (it keeps its own vertical offset in `dy`).
            flying = FlyOut(id: p.id, liked: liked, superLike: superLike, dy: drag.height)
            drag = .zero
        }
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            // By now the next card already sits exactly where the top card goes, so swapping
            // the data without animation is invisible.
            var t = Transaction(animation: nil)
            t.disablesAnimations = true
            withTransaction(t) {
                liked ? app.like(p, opener: opener, superLike: superLike) : app.pass(p)
                drag = .zero
                flying = nil
            }
        }
    }

    /// Confirm before spending a super like; with none left, the extras sheet offers packs.
    private func askSuperLike(_ p: Profile) {
        guard app.superLikes > 0 else {
            Haptics.warning()
            extras = .superLike
            return
        }
        Haptics.tap()
        withoutAnimation { superLikeTarget = p }
    }

    private func withoutAnimation(_ body: () -> Void) {
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t, body)
    }

    // MARK: Top bar

    private var topBar: some View {
        // Same paddings as TabHeader; Discover doesn't scroll, so it's a plain row.
        // Boosts sit on the screen's centre line unless the wordmark needs the room.
        CenterUnlessCrowded {
            HStack(spacing: 6) {
                Wordmark(size: 30, color: DS.Palette.ink)
                // Plus members get the spark next to the wordmark, as on the paywall.
                if app.isPremium {
                    SparkPlus()
                        .fill(DS.Palette.lime)
                        .frame(width: 30, height: 21)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Plus")
                }
            }
            .fixedSize() // the wordmark never truncates; the spacers give way
            .layoutPriority(1)
            .padding(.leading, DS.Space.xs)
            .animation(Motion.bouncy, value: app.isPremium)
            HStack(spacing: 6) {
                if Self.likesInHeader, !app.likedMe.isEmpty {
                    LikesChip(likers: app.likedMe, unlocked: app.isPremium) {
                        Haptics.tap()
                        if app.isPremium { showLikes = true } else { showLikesPaywall = true }
                    }
                }
                wallet
            }
            Button {
                Haptics.tap()
                showFilters = true
            } label: {
                // The count lives inside the pill (never a badge hanging off its corner).
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.bold))
                        .foregroundStyle(DS.Palette.ink)
                    if app.filters.activeCount > 0 {
                        Text("\(app.filters.activeCount)")
                            .font(.caption.weight(.heavy).monospacedDigit())
                            .foregroundStyle(DS.Palette.onLime)
                            .contentTransition(.numericText())
                            .frame(minWidth: 22, minHeight: 22)
                            .background(DS.Palette.lime, in: .circle)
                            .transition(.scale(0.6).combined(with: .opacity))
                    }
                }
                .padding(.leading, app.filters.activeCount > 0 ? 11 : 0)
                .padding(.trailing, app.filters.activeCount > 0 ? 9 : 0)
                .frame(minWidth: 40, minHeight: 40)
                .background(DS.Palette.canvas, in: .capsule)
                .animation(Motion.snappy, value: app.filters.activeCount)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(PressScaleStyle(scale: 0.95))
            .accessibilityLabel("Filters, \(app.filters.distanceLabel), \(app.filters.activeCount) active")
        }
        .frame(height: 44)
        .padding(.horizontal, DS.Space.lg - DS.Space.md) // the stack already pads md
        .padding(.top, DS.Space.xs)
        .padding(.bottom, DS.Space.sm)
    }

    // MARK: Wallet

    /// Boosts left, or the running boost as a live clock. Opens the boost sheet.
    private var wallet: some View {
        BoostChip(boosts: app.boosts, endsAt: app.boostEndsAt) {
            Haptics.tap()
            extras = .boost
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: DS.Space.lg) {
            // Ghost undo: a premium feature, free users hit the paywall.
            Button {
                if app.isPremium {
                    withAnimation(Motion.bouncy) { app.undo() }
                } else {
                    Haptics.tap()
                    showPaywall = true
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(PressScaleStyle(scale: 0.88))
            .disabled(!app.canUndo)
            .opacity(app.canUndo ? 1 : 0.35)
            .accessibilityLabel("Undo last swipe")

            // While dragging, the button on that side grows; the other one shrinks back a little.
            Button {
                if let p = app.topCard { commit(p, liked: false) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 72, height: 72)
                    .glassEffect(.regular, in: .circle)
                    .scaleEffect(1 + max(0, -progress) * 0.18 - max(0, progress) * 0.08)
                    .symbolEffect(.bounce, value: passBurst)
            }
            .buttonStyle(PressScaleStyle(scale: 0.88))
            .accessibilityLabel("Pass")

            Button {
                if let p = app.topCard { commit(p, liked: true) }
            } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(DS.Palette.onLike)
                    .frame(width: 72, height: 72)
                    .background(DS.Palette.like, in: .circle)
                    .scaleEffect(1 + max(0, progress) * 0.18 - max(0, -progress) * 0.08)
                    .symbolEffect(.bounce, value: likeBurst)
                    .overlay { HeartBurst(trigger: likeBurst) }
            }
            .buttonStyle(PressScaleStyle(scale: 0.88))
            .accessibilityLabel("Like")

            // Same width as undo, so cross and heart stay centered.
            Button {
                if let p = app.topCard { askSuperLike(p) }
            } label: {
                SuperLikeCountMark(count: app.superLikes, size: 52)
                    .symbolEffect(.bounce, value: superBurst)
            }
            .buttonStyle(PressScaleStyle(scale: 0.88))
            .accessibilityLabel("Super like, \(app.superLikes) left")
        }
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: progress)
        .frame(maxWidth: .infinity)
    }

    /// True when people remain in the queue but the filters hide them all.
    private var filteredOut: Bool { !app.queue.isEmpty && app.deck.isEmpty }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            if filteredOut {
                @Bindable var app = app
                TooTightCard(filters: $app.filters) { showFilters = true }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else {
                Spacer()
                // No loose text on the sage canvas: the message sits in a white block.
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    Text("That's everyone nearby.")
                        .font(.display(44))
                        .displayLeading(44)
                        .foregroundStyle(DS.Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("New people join every morning. Meanwhile, your matches are waiting in Chats.")
                        .font(.body)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
                Spacer()
                Button("Go to chats") { app.tab = .chats }
                    .buttonStyle(.drafftPrimary)
                Button("See profiles again") { withAnimation(Motion.bouncy) { app.resetDeck() } }
                    .buttonStyle(.drafftSecondary)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .frame(maxHeight: .infinity)
    }
}

/// Small hearts that pop out of the like button.
struct HeartBurst: View {
    let trigger: Int
    @State private var fired = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                let angle = Angle.degrees(Double(i) / 7 * 360 - 90)
                Image(systemName: "heart.fill")
                    .font(.system(size: CGFloat(10 + (i % 3) * 3)))
                    .foregroundStyle(i.isMultiple(of: 2) ? DS.Palette.like : DS.Palette.likeActive)
                    .offset(x: fired ? cos(angle.radians) * 64 : 0, y: fired ? sin(angle.radians) * 64 : 0)
                    .scaleEffect(fired ? 1 : 0.2)
                    .opacity(fired ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .opacity(trigger == 0 || reduceMotion ? 0 : 1)
        .onChange(of: trigger) {
            guard !reduceMotion else { return }
            fired = false
            withAnimation(.easeOut(duration: 0.4)) { fired = true }
        }
        .accessibilityHidden(true)
    }
}

/// Three items in a row: first on the left, last on the right, the middle one on the exact
/// centre line. When the left item is too wide for that, the middle one slides right just
/// enough to keep a gap (and never runs into the right item).
struct CenterUnlessCrowded: Layout {
    var gap: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let h = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +), height: h)
    }

    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let s = subviews.map { $0.sizeThatFits(.unspecified) }
        subviews[0].place(at: CGPoint(x: b.minX, y: b.midY), anchor: .leading, proposal: ProposedViewSize(s[0]))
        subviews[2].place(at: CGPoint(x: b.maxX, y: b.midY), anchor: .trailing, proposal: ProposedViewSize(s[2]))
        let minX = b.minX + s[0].width + gap
        let maxX = b.maxX - s[2].width - gap - s[1].width
        let x = min(max(b.midX - s[1].width / 2, minX), max(minX, maxX))
        subviews[1].place(at: CGPoint(x: x, y: b.midY), anchor: .leading, proposal: ProposedViewSize(s[1]))
    }
}

/// Veil over the cards waiting behind the top one, plus a faint edge in dark mode so stacked
/// cards don't merge with the page.
private struct DeckVeil: View {
    let amount: Double
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .fill(DS.Palette.deckVeil)
                .opacity(amount)
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .strokeBorder(DS.Palette.blockEdge, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
