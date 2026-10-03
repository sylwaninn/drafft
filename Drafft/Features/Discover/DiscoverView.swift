import Nuke
import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.displayScale) private var displayScale
    @State private var drag: CGSize = .zero
    /// Cards on their way out. Each one leaves the deck (and the data) the moment it's swiped and
    /// finishes its flight in its own layer, so the next card is in play at once: fast swipes never
    /// wait for the previous card to land.
    @State private var flying: [FlyOut] = []
    @State private var deckSize: CGSize = .zero
    /// Set by the swipe that empties the stack, cleared once the empty state has shown it: only that
    /// moment plays the empty state's entrance.
    @State private var emptiedBySwipe = false
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

    struct FlyOut: Identifiable, Equatable {
        let id = UUID()
        let profile: Profile
        let liked: Bool
        var superLike = false
        /// Where the drag left it: the flight starts from there.
        var start: CGSize = .zero
        static func == (l: FlyOut, r: FlyOut) -> Bool { l.id == r.id }
    }

    /// What the photo window is aimed at: the next cards, and the size they're drawn at.
    private struct PhotoAim: Equatable {
        let ids: [String]
        let size: CGSize
    }

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
                ZStack(alignment: .top) {
                    if app.deck.isEmpty {
                        // Right away, even while the last card is still flying over it.
                        switch app.deckState {
                        case .loading:
                            loadingState
                        case .failed(let message):
                            failedState(message)
                                .padding(.bottom, DS.Space.xl)
                        case .idle, .loaded:
                            emptyState
                                .padding(.bottom, DS.Space.xl)
                        }
                    } else {
                        VStack(spacing: 0) {
                            deck
                                .zIndex(1)
                            // Same space above and below: centred between the cards and the tab bar.
                            actions
                                .padding(.vertical, DS.Space.lg)
                                .zIndex(2)
                        }
                    }
                    flyingLayer
                }
                .zIndex(1)
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
        let follow: CGFloat = i == 1 ? abs(progress) * 0.5 : 0
        return max(0, CGFloat(i) - follow)
    }

    private var deck: some View {
        GeometryReader { geo in
            ZStack {
                // One extra card is kept hidden at the back so it can fade in when the stack moves up.
                ForEach(Array(app.deck.prefix(4).enumerated().reversed()), id: \.element.id) { i, p in
                    let isTop = i == 0
                    let d = depth(i)
                    SwipeCard(profile: p, me: app.me, progress: isTop ? progress : 0, isTop: isTop,
                              photoPriority: photoPriority(i)) {
                        open(p)
                    }
                    .frame(width: geo.size.width, height: geo.size.height - 28)
                    // Cards behind are veiled in sage so the top card reads as the one in play.
                    .overlay { DeckVeil(amount: isTop ? 0 : veilAmount(d)) }
                    .shadow(color: .black.opacity(isTop ? 0.22 : Double(max(0, 1 - d)) * 0.22), radius: 20, y: 12)
                    .scaleEffect(1 - d * 0.07, anchor: .bottom)
                    .offset(y: d * 14)
                    .opacity(d > 2.5 ? 0 : 1)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(isTop ? drag : .zero)
                    .rotationEffect(.degrees(isTop ? Double(drag.width / 18) : 0), anchor: .bottom)
                    .gesture(isTop ? swipe(p) : nil)
                    .allowsHitTesting(isTop)
                    .zIndex(isTop ? 10 : Double(4 - i))
                    .accessibilityHidden(!isTop)
                    .accessibilityActions {
                        Button("Like") { commit(p, liked: true) }
                        Button("Super like") { askSuperLike(p) }
                        Button("Pass") { commit(p, liked: false) }
                        Button("Open profile") { open(p) }
                    }
                    // Undo brings a card back on top with a soft scale-in.
                    .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .identity))
                }
            }
            // The stack moves up as each swiped card leaves the data.
            .animation(.smooth(duration: 0.26, extraBounce: 0.04), value: app.deck.first?.id)
            .onAppear { deckSize = geo.size }
            .onChange(of: geo.size) { _, size in deckSize = size }
            // The next cards' photos, fetched ahead and re-aimed on every swipe (`PhotoWindow`): what
            // leaves the window is cancelled, so the card in play keeps the line.
            .task(id: PhotoAim(ids: app.deck.prefix(12).map(\.id), size: geo.size)) {
                PhotoWindow.deck.aim(deck: Array(app.deck.prefix(12)), onScreen: 4,
                                     points: CGSize(width: geo.size.width, height: geo.size.height - 28), scale: displayScale)
            }
            .onDisappear { PhotoWindow.deck.clear() }
            // A card looked at for a while is likelier to be opened: its profile's first photo starts, under
            // the deck's own. A swipe cancels it; never ahead of every card, most are never opened.
            .task(id: app.deck.first?.id) {
                guard let top = app.deck.first, !NetworkQuality.shared.isLimited else { return }
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                await Images.warm(top.portrait, scale: displayScale, priority: .low)
            }
            #if DECK_PHOTO_METRICS
            .onChange(of: app.deck.first?.portrait, initial: true) { _, top in
                DeckPhotoMetrics.track(app.deck.prefix(4).map(\.portrait))
                DeckPhotoMetrics.becameTop(top)
            }
            #endif
        }
    }

    /// Swiped cards finishing their flight above everything, the empty state included. Never
    /// touchable: the card under them is already in play.
    private var flyingLayer: some View {
        ZStack {
            ForEach(flying) { f in
                FlyingCard(flyOut: f, me: app.me, width: deckSize.width)
                    .frame(width: deckSize.width, height: max(0, deckSize.height - 28))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Opens a profile, its first photo already downloading at the gallery's size (`Images.warm`): the
    /// sheet's rise gives it a head start, and the card's own copy stands in until it's there.
    private func open(_ p: Profile) {
        Task { await Images.warm(p.portrait, scale: displayScale, priority: .high) }
        detail = p
    }

    /// The card in play's photo first. On a limited connection every small copy of the window comes
    /// before it (`PhotoWindow`), and the cards behind it get their full one last.
    private func photoPriority(_ i: Int) -> ImageRequest.Priority {
        let limited = NetworkQuality.shared.isLimited
        if i == 0 { return limited ? .high : .veryHigh }
        if limited { return .veryLow }
        return i == 1 ? .high : .normal
    }

    private func veilAmount(_ d: CGFloat) -> Double {
        Double(min(d, 1)) * 0.55 + Double(max(0, d - 1)) * 0.2
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
        // Out of likes or super likes: the card springs back and the extras sheet explains why.
        if superLike && app.superLikes == 0 || liked && !superLike && !app.canLike {
            Haptics.warning()
            withAnimation(Motion.bouncy) { drag = .zero }
            extras = superLike ? .superLike : .likes
            return
        }
        liked ? Haptics.thump() : Haptics.tap()
        if superLike { superBurst += 1 } else if liked { likeBurst += 1 } else { passBurst += 1 }
        // The card leaves the deck and the data now; its flight carries on in `flyingLayer`, so the
        // next card is in play at once and a quick run of swipes never waits.
        let flyOut = FlyOut(profile: p, liked: liked, superLike: superLike, start: drag)
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) { drag = .zero }
        flying.append(flyOut)
        app.swipe(p, liked: liked, superLike: superLike, opener: opener)
        if app.deck.isEmpty { emptiedBySwipe = true }
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            flying.removeAll { $0.id == flyOut.id }
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
                // Plus members get the spark next to the wordmark, as a round sticker (the one on the
                // Get drafft tempo card, smaller).
                if app.isPremium {
                    StillSticker(tempoSize: 30)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityElement(children: .ignore)
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
                    Image("tuning-2")
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
                Image("undo-left")
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
                Image("close")
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
                Image("heart")
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

    /// The first batch on its way (nothing kept from last time).
    private var loadingState: some View {
        ProgressView()
            .controlSize(.large)
            .tint(DS.Palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading profiles")
    }

    /// The deck couldn't be read (offline, or the server refused): why, and a retry.
    private func failedState(_ message: String) -> some View {
        EmptyStateView(art: .discover, title: "No profiles right now.", message: LocalizedStringKey(message)) {
            Button("Try again") {
                Haptics.tap()
                app.loadDeck(.refresh)
            }
            .buttonStyle(.drafftPrimaryFit)
        }
        .frame(maxHeight: .infinity)
    }

    /// The stack ran out (filtered or not): the same screen either way.
    private var emptyState: some View {
        DeckEmptyView(animate: emptiedBySwipe, onChats: { app.tab = .chats }, onFilters: { showFilters = true })
            .onAppear { DispatchQueue.main.async { emptiedBySwipe = false } }
            .padding(.horizontal, DS.Space.md)
    }
}

/// A swiped card finishing its flight: starts where the drag left it and leaves the screen with
/// its LIKE/PASS stamp fully shown, in one smooth move.
private struct FlyingCard: View {
    let flyOut: DiscoverView.FlyOut
    let me: Profile
    let width: CGFloat
    @State private var gone = false

    var body: some View {
        SwipeCard(profile: flyOut.profile, me: me, progress: flyOut.liked ? 1 : -1, isTop: true) {}
            .shadow(color: .black.opacity(0.22), radius: 20, y: 12)
            .offset(gone ? end : flyOut.start)
            .rotationEffect(.degrees(gone ? endRotation : Double(flyOut.start.width / 18)), anchor: .bottom)
            .onAppear { withAnimation(.smooth(duration: 0.26, extraBounce: 0.04)) { gone = true } }
    }

    private var end: CGSize {
        if flyOut.superLike { return CGSize(width: 0, height: -width * 2.2) }
        return CGSize(width: (flyOut.liked ? 1 : -1) * width * 1.6, height: flyOut.start.height + 40)
    }

    private var endRotation: Double { flyOut.superLike ? 0 : (flyOut.liked ? 18 : -18) }
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
                Image("heart")
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
