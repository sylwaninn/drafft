import SwiftUI

/// Likes tab: everyone who already liked you, as a grid of cards. With drafft tempo, open a profile and
/// like back to match. Without it the server sends no identity, only a ThumbHash per like
/// (`AppModel.blurredLikes`): the grid shows those previews and a night block offers the unlock.
struct LikesTabView: View {
    @Environment(AppModel.self) private var app
    @State private var scrollOffset: CGFloat = 0
    @State private var open: Profile?
    @State private var showPaywall = false

    private let columns = [GridItem(.flexible(), spacing: DS.Space.sm), GridItem(.flexible(), spacing: DS.Space.sm)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    if app.isPremium {
                        if app.likedMe.isEmpty {
                            emptyOrLoading
                        } else {
                            LazyVGrid(columns: columns, spacing: DS.Space.sm) {
                                ForEach(app.likedMe) { p in
                                    Button {
                                        Haptics.tap()
                                        open = p
                                    } label: { card(p) }
                                    .buttonStyle(PressScaleStyle(scale: 0.97))
                                    .accessibilityLabel("\(p.name), \(p.age). Open profile")
                                }
                            }
                        }
                    } else if app.blurredLikes.isEmpty {
                        emptyOrLoading
                    } else {
                        unlockBlock
                        LazyVGrid(columns: columns, spacing: DS.Space.sm) {
                            ForEach(app.blurredLikes) { like in
                                Button {
                                    Haptics.tap()
                                    showPaywall = true
                                } label: { blurredCard(like) }
                                .buttonStyle(PressScaleStyle(scale: 0.97))
                                .accessibilityLabel("Someone who likes you. Unlock with drafft tempo")
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xl)
            }
            .trackingScrollOffset($scrollOffset)
            // Live afterwards through the `wallet` event and each reconnection (`UserChannel`).
            .task { await app.loadLikes() }
            .background(DS.Palette.canvasSoft)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .topBar {
                TabHeader(offset: scrollOffset) { TabTitle(text: L("Likes")) }
            }
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
    }

    private var unlockBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(app.blurredLikes.count == 1 ? "1 person likes you." : "\(app.blurredLikes.count) people like you.")
                .font(.display(30))
                .displayLeading(30)
                .foregroundStyle(DS.Palette.accentOnNight)
                .accessibilityAddTraits(.isHeader)
            Text(branded: L("See who, and match in one tap with drafft tempo."), font: .subheadline,
                 tierColor: DS.Palette.accentOnNight)
                .foregroundStyle(.white.opacity(0.72))
            Button("See who likes you") {
                Haptics.tap()
                showPaywall = true
            }
            .buttonStyle(.drafftPrimary)
            .draftTrail(RoundedRectangle(cornerRadius: DS.Radius.xl), step: CGSize(width: -6, height: 0))
            .padding(.leading, 12)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBlock()
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

    /// A like on the free plan: the server's ThumbHash (already a blur), a lock, and a star for a
    /// super like.
    private func blurredCard(_ like: BlurredLike) -> some View {
        Rectangle()
            .fill(DS.Palette.sage)
            .frame(height: 230)
            .overlay {
                if let preview = like.preview {
                    Image(uiImage: preview).resizable().interpolation(.medium).scaledToFill()
                }
            }
            .overlay {
                Image("lock-keyhole-minimalistic")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.18), in: .circle)
            }
            .overlay(alignment: .topTrailing) {
                if like.superLike {
                    Image("star")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(DS.Palette.onAccentOnNight)
                        .frame(width: 30, height: 30)
                        .background(DS.Palette.accentOnNight, in: .circle)
                        .padding(DS.Space.sm)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(.rect(cornerRadius: DS.Radius.xl))
    }

    private func card(_ p: Profile) -> some View {
        Photo(name: p.portrait, side: 180)
            .frame(height: 230)
            .overlay {
                // design-lint: allow gradient - photo scrim under the name
                LinearGradient(stops: [.init(color: .clear, location: 0.5),
                                       .init(color: DS.Palette.night.opacity(0.8), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                ProfileIdentity(profile: p, nameSize: 22, showsLocation: false, showsSuperLike: true)
                    .padding(DS.Space.md)
            }
            .clipShape(.rect(cornerRadius: DS.Radius.xl))
    }
}
