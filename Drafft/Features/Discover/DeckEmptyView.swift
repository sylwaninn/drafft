import SwiftUI

/// Discover when the stack runs out, filtered or not: one screen. A night block with lime contours
/// (the house signature), its lime headline drafting like the app icon: the ghosts tuck in behind it
/// as it arrives (the one authored moment here). Then the two ways on: your chats, or wider filters.
struct DeckEmptyView: View {
    let onChats: () -> Void
    let onFilters: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tucked = false

    var body: some View {
        VStack(spacing: DS.Space.xl) {
            Spacer(minLength: 0)

            // No loose text on the sage canvas: headline and message sit in the block.
            VStack(spacing: DS.Space.lg) {
                headline
                Text("You've seen everyone around you for now. Widen your filters or catch up with your matches in Chats.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.xxl)
            .frame(maxWidth: .infinity)
            .draftBlock(DS.Palette.night, seed: BackdropSeed.deckEmpty, tint: DS.Palette.lime)

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
            guard !reduceMotion else { tucked = true; return }
            tucked = false
            withAnimation(Motion.progress.delay(0.12)) { tucked = true }
        }
    }

    /// The lead line with two fading copies behind it, like riders in each other's slipstream. On
    /// arrival the copies start stacked under the lead and slide back into place, one after the other.
    private var headline: some View {
        ZStack {
            ForEach((0..<3).reversed(), id: \.self) { i in
                Text("Finish line.")
                    .font(.display(52, relativeTo: .largeTitle))
                    .lineSpacing(-52 * 0.3)
                    .tracking(-52 * 0.01)
                    .multilineTextAlignment(.center)
                    // Same lime for the lead and its ghosts, only fading, like the app icon.
                    .foregroundStyle(DS.Palette.lime.opacity([1, 0.3, 0.14][i]))
                    .offset(x: tucked ? -CGFloat(i) * 9 : 0)
                    .opacity(i == 0 || tucked ? 1 : 0)
                    .animation(reduceMotion ? nil : Motion.progress.delay(0.12 + Double(i) * 0.08), value: tucked)
                    .accessibilityHidden(i > 0)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityAddTraits(.isHeader)
    }
}
