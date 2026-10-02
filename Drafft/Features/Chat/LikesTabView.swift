import SwiftUI

/// Likes tab: a banner with how many people like you, then everyone who already liked you as a grid of
/// equal portraits (`LikesGrid`).
///
/// - Without drafft tempo the server sends no identity, only blurred previews per like
///   (`AppModel.blurredLikes`: a ThumbHash, and a blurred copy of the photo when the backend has one):
///   the tiles are those previews, the banner counts them, and the one action, pinned at the bottom,
///   opens the paywall (so does any tile).
/// - With drafft tempo the tiles are their photos: open a profile, or like back right from the tile.
struct LikesTabView: View {
    @Environment(AppModel.self) private var app
    @State private var scrollOffset: CGFloat = 0
    @State private var open: Profile?
    @State private var showPaywall = false
    @Environment(\.tabsOnScreen) private var onScreen
    @State private var shown = false

    private var locked: Bool { !app.isPremium && !app.blurredLikes.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if app.isPremium {
                        if app.likedMe.isEmpty {
                            emptyOrLoading
                        } else {
                            LikesGrid(items: app.likedMe, visitKey: "likes-tab") {
                                LikesBanner.tempo(count: app.likedMe.count)
                            } tile: { p in
                                EveryMinute { now in
                                    LikeTile(profile: p, now: now) {
                                        Haptics.tap()
                                        open = p
                                    } onLike: {
                                        app.swipe(p, liked: true)
                                    }
                                }
                            }
                        }
                    } else if app.blurredLikes.isEmpty {
                        emptyOrLoading
                    } else {
                        LikesGrid(items: app.blurredLikes, visitKey: "likes-tab") {
                            LikesBanner.locked(count: app.blurredLikes.count)
                        } tile: { like in
                            EveryMinute { now in
                                Button {
                                    Haptics.tap()
                                    showPaywall = true
                                } label: { LockedLikeTile(like: like, now: now) }
                                .buttonStyle(PressScaleStyle(scale: 0.97))
                                .accessibilityLabel(like.superLike ? "Someone super liked you. Unlock with drafft tempo"
                                                                   : "Someone who likes you. Unlock with drafft tempo")
                                .accessibilityValue(LikeAge.text(of: like.likedAt, at: now) ?? "")
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.xs)
                .padding(.bottom, DS.Space.xl)
            }
            .trackingScrollOffset($scrollOffset)
            // Live afterwards through the `like` and `wallet` events and each reconnection (`UserChannel`).
            .task { await app.loadLikes() }
            .background(DS.Palette.canvasSoft)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .topBar {
                TabHeader(offset: scrollOffset) { TabTitle(text: L("Likes")) }
            }
            .bottomBar {
                if locked { unlockButton }
            }
            .animation(Motion.snappy, value: locked)
            // Same presentation and actions as a profile opened from Discover.
            .sheet(item: $open) { p in
                Group {
                    NavigationStack {
                        ProfileDetailView(profile: p, mode: .discover) { liked, opener in
                            open = nil
                            app.swipe(p, liked: liked, opener: opener)
                        } onSuperLike: { opener in
                            open = nil
                            app.swipe(p, liked: true, superLike: true, opener: opener)
                        }
                    }
                }
                .sheetSurface()
            }
            .sheet(isPresented: $showPaywall) {
                Group {
                    PaywallView(headline: L("See who likes you."),
                                pitch: L("drafft tempo shows everyone who already liked you, so you can match in one tap."),
                                unlockedTitle: L("See who likes you"))
                }
                .sheetSurface()
            }
        }
        // Each time the tab is shown (not during the walk under the splash): how many likes waited,
        // and whether they could be seen.
        .onAppear {
            shown = true
            if onScreen { trackViewed() }
        }
        .onChange(of: onScreen) { _, now in
            if now && shown { trackViewed() }
        }
        .onDisappear { shown = false }
    }

    private func trackViewed() {
        Telemetry.track(.likesViewed(count: app.likedMeCount, premium: app.isPremium))
    }

    /// The one action without drafft tempo, always on screen above the tab bar.
    private var unlockButton: some View {
        Button {
            Haptics.tap()
            showPaywall = true
        } label: {
            Label("See who likes you", image: "user-heart")
        }
        .buttonStyle(.drafftPrimary)
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Nobody yet only once the list was read: before, a spinner; after a failed first read, a retry.
    @ViewBuilder
    private var emptyOrLoading: some View {
        switch app.likesLoad {
        case .loaded: emptyState
        case .failed(let offline):
            ListLoadFailureView(art: .likes, title: "Your likes couldn't load", offline: offline) {
                app.likesLoad = .loading
                Task { await app.loadLikes() }
            }
            .containerRelativeFrame(.vertical) { h, _ in h * 0.8 }
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical) { h, _ in h * 0.8 }
        }
    }

    private var emptyState: some View {
        EmptyStateView(art: .likes, title: "No likes yet.",
                       message: "A sport photo and a voice intro help. New likes land here.") {
            Button("Back to Discover") { app.tab = .discover }
                .buttonStyle(.drafftPrimaryFit)
        }
        // The middle of the visible page, under the header.
        .containerRelativeFrame(.vertical) { h, _ in h * 0.8 }
    }
}
