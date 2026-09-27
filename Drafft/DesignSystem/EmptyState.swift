import SwiftUI

/// An empty tab: a quiet illustration on the page, a title, one line of text, and an action if
/// there is one to take. Sits in the middle of the space it is given.
struct EmptyStateView<Actions: View>: View {
    let art: EmptyStateArt
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: DS.Space.xl) {
            EmptyStateIllustration(art: art)
            VStack(spacing: DS.Space.sm) {
                Text(title)
                    .font(.display(22, relativeTo: .title2))
                    .foregroundStyle(DS.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(DS.Palette.body)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(art: EmptyStateArt, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.init(art: art, title: title, message: message) { EmptyView() }
    }
}

/// What each empty tab draws: its tab-bar icon, cut out of a small piece of terrain.
struct EmptyStateArt {
    /// The sign's outline, drawn in the accent.
    let symbol: String
    /// Its solid shape, cut out of the map (a little wider, so the lines stop short of the outline).
    let cutout: String
    /// Seeds the relief: each tab has its own map.
    let seed: String

    static let likes = EmptyStateArt(symbol: "heart", cutout: "heart.fill", seed: "likes")
    static let sessions = EmptyStateArt(symbol: "flag.2.crossed", cutout: "flag.2.crossed.fill", seed: "sessions")
    static let chats = EmptyStateArt(symbol: "bubble.left.and.bubble.right", cutout: "bubble.left.and.bubble.right.fill", seed: "chats")
}

/// The sign in reserve: a small, faint contour map whose lines stop around the sign, so it reads as
/// a gap in the terrain, with only a thin accent outline drawn. Nothing else around it.
struct EmptyStateIllustration: View {
    let art: EmptyStateArt
    /// The map's lines and the outline. The accent, but for a closed account (negative).
    var tint: Color = DS.Palette.lime
    /// How much the map shows: 1 on the page, more on a night background.
    var strength = 1.0

    private let width: CGFloat = 200
    private let height: CGFloat = 150
    private let glyph: CGFloat = 54

    var body: some View {
        ZStack {
            MorphingContours(from: TerrainField(seed: "empty-\(art.seed)"),
                             to: TerrainField(seed: "empty-\(art.seed)"),
                             progress: 1, tint: tint, levels: 12, strength: strength)
                .mask {
                    ZStack {
                        // design-lint: allow gradient - a mask: the map's edge melts into the page
                        RadialGradient(colors: [.black, .clear], center: .center,
                                       startRadius: height * 0.18, endRadius: width * 0.52)
                        Image(systemName: art.cutout)
                            .font(.system(size: glyph * 1.22, weight: .black))
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
            Image(systemName: art.symbol)
                .font(.system(size: glyph, weight: .light))
                .foregroundStyle(tint)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}
