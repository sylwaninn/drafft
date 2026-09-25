import SwiftUI

/// Discover when the stack runs out, filtered or not: one screen, kept quiet. A white block like the
/// app's other empty states, a round lime flag (the finish line), a short title and what to do next.
/// The flag settles in as the screen appears; nothing else moves.
struct DeckEmptyView: View {
    let onChats: () -> Void
    let onFilters: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: DS.Space.xl) {
            Spacer(minLength: 0)

            // No loose text on the sage canvas: everything sits in the white block.
            VStack(spacing: DS.Space.md) {
                DraftGlyph(symbol: "flag.checkered", size: 56)
                    .scaleEffect(shown ? 1 : 0.6)
                    .opacity(shown ? 1 : 0)
                    .padding(.bottom, DS.Space.xs)
                Text("Finish line.")
                    .font(.display(30, relativeTo: .title))
                    .foregroundStyle(DS.Palette.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("You've seen everyone around you for now. Widen your filters or catch up with your matches in Chats.")
                    .font(.body)
                    .foregroundStyle(DS.Palette.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.xxl)
            .frame(maxWidth: .infinity)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))

            Spacer(minLength: 0)

            VStack(spacing: DS.Space.xs) {
                Button(action: onChats) {
                    Label("Go to chats", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(.drafftPrimary)
                .draftTrail(RoundedRectangle(cornerRadius: DS.Radius.xl), step: CGSize(width: -6, height: 0))
                .padding(.leading, 12)

                Button("Adjust filters", action: onFilters)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentInk)
                    .buttonStyle(.textLink(fullWidth: true))
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(Motion.bouncy.delay(0.1)) { shown = true }
        }
    }
}
