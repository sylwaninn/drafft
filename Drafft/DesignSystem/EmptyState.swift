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
            VStack(spacing: DS.Space.md) {
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
            }
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

/// What each empty tab draws: its tab-bar icon.
struct EmptyStateArt {
    /// The sign's outline, drawn in the accent.
    let symbol: String

    static let discover = EmptyStateArt(symbol: "flame")
    static let likes = EmptyStateArt(symbol: "heart")
    static let sessions = EmptyStateArt(symbol: "flag.2.crossed")
    static let chats = EmptyStateArt(symbol: "bubble.left.and.bubble.right")
}

/// The sign in reserve: a thin accent outline, nothing else around it.
struct EmptyStateIllustration: View {
    let art: EmptyStateArt
    /// The outline. The accent, but for a closed account (negative).
    var tint: Color = DS.Palette.lime

    private let width: CGFloat = 200
    private let height: CGFloat = 64
    private let glyph: CGFloat = 54

    var body: some View {
        Image(systemName: art.symbol)
            .font(.system(size: glyph, weight: .light))
            .foregroundStyle(tint)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}
