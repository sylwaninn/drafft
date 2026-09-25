import SwiftUI

/// Branded empty state for Discover when the filters hide everyone. It takes the place of the card
/// stack: an icon drafting its own ghosts, a friendly line, and a way to loosen the filters.
struct TooTightCard: View {
    @Binding var filters: DiscoverFilters
    let onAdjust: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: DS.Space.xl) {
            Spacer(minLength: 0)

            // No loose text on the sage canvas: headline and message sit in a white block.
            VStack(spacing: DS.Space.lg) {
                // Headline drafting its own ghosts (user-requested exception to the no-trail-on-text rule).
                ZStack {
                    ForEach((0..<3).reversed(), id: \.self) { i in
                        Text("No one\nhere.")
                            .font(.display(52, relativeTo: .largeTitle))
                            .lineSpacing(-52 * 0.3)
                            .tracking(-52 * 0.01)
                            .multilineTextAlignment(.center)
                            // Same ink for the lead and its ghosts, only fading, like the wordmark.
                            .foregroundStyle(DS.Palette.ink.opacity([1, 0.28, 0.12][i]))
                            .offset(x: -CGFloat(i) * 9)
                    }
                }
                .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
                .opacity(appeared || reduceMotion ? 1 : 0)
                .padding(.vertical, DS.Space.xs)
                .accessibilityLabel("No one here")
                .accessibilityAddTraits(.isHeader)

                Text("Nobody nearby fits your filters right now. Loosen them a little and new people will show up.")
                    .font(.body)
                    .foregroundStyle(DS.Palette.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))

            Spacer(minLength: 0)

            VStack(spacing: DS.Space.xs) {
                Button {
                    Haptics.success()
                    withAnimation(Motion.bouncy) { filters = filters.loosened() }
                } label: {
                    Label("Clear filters", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.drafftPrimary)
                .draftTrail(RoundedRectangle(cornerRadius: DS.Radius.xl), step: CGSize(width: -6, height: 0))
                .padding(.leading, 12)

                Button("Adjust filters", action: onAdjust)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentInk)
                    .buttonStyle(.textLink(fullWidth: true))
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(Motion.bouncy.delay(0.05)) { appeared = true } }
    }
}
