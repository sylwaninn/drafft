import SwiftUI

/// Likes tab: everyone who already liked you, as a grid of cards. Without Plus the faces are
/// blurred and a night block explains the unlock; with Plus, open a profile and like back to match.
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
                    if app.likedMe.isEmpty {
                        emptyState
                    } else {
                        if !app.isPremium { unlockBlock }
                        LazyVGrid(columns: columns, spacing: DS.Space.sm) {
                            ForEach(app.likedMe) { p in
                                Button {
                                    Haptics.tap()
                                    if app.isPremium { open = p } else { showPaywall = true }
                                } label: { card(p) }
                                .buttonStyle(PressScaleStyle(scale: 0.97))
                                .accessibilityLabel(app.isPremium ? "\(p.name), \(p.age). Open profile" : "Someone who likes you. Unlock with drafft tempo")
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xl)
            }
            .trackingScrollOffset($scrollOffset)
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
                            if liked { app.like(p, opener: opener) } else { app.pass(p) }
                        } onSuperLike: { opener in
                            open = nil
                            app.like(p, opener: opener, superLike: true)
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
            Text(app.likedMe.count == 1 ? "1 person likes you." : "\(app.likedMe.count) people like you.")
                .font(.display(30))
                .displayLeading(30)
                .foregroundStyle(DS.Palette.lime)
                .accessibilityAddTraits(.isHeader)
            Text(branded: L("See who, and match in one tap with drafft tempo."), font: .subheadline,
                 tierColor: DS.Palette.lime)
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
        .draftBlock(DS.Palette.night, seed: BackdropSeed.nextSession, tint: DS.Palette.lime)
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

    private func card(_ p: Profile) -> some View {
        // Locked: a copy with the blur baked in, not a live blur on every card.
        Photo(name: p.portrait, side: 180, blur: app.isPremium ? 0 : 18)
            .frame(height: 230)
            .overlay {
                // design-lint: allow gradient - photo scrim under the name
                LinearGradient(stops: [.init(color: .clear, location: 0.5),
                                       .init(color: DS.Palette.night.opacity(0.8), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                if app.isPremium {
                    ProfileIdentity(profile: p, nameSize: 22, showsLocation: false, showsSuperLike: true)
                        .padding(DS.Space.md)
                }
            }
            .overlay {
                if !app.isPremium {
                    Image(systemName: "lock.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.18), in: .circle)
                }
            }
            .clipShape(.rect(cornerRadius: DS.Radius.xl))
    }
}
