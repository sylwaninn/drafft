import SwiftUI

/// Header chip on Discover: who already liked you. Two stacked faces (blurred until Plus) and
/// the count. Opens the likes grid, or the paywall.
struct LikesChip: View {
    let likers: [Profile]
    let unlocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                HStack(spacing: -9) {
                    ForEach(Array(likers.prefix(2).enumerated()), id: \.element.id) { i, p in
                        Photo(name: p.portrait, side: 24, blur: unlocked ? 0 : 4)
                            .frame(width: 24, height: 24)
                            .clipShape(.circle)
                            .overlay(Circle().strokeBorder(DS.Palette.canvas, lineWidth: 2))
                            .zIndex(Double(2 - i))
                    }
                }
                Text("\(likers.count)")
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText())
                // An accent dot says "new", inside the chip: the one accent on it.
                Circle().fill(DS.Palette.lime)
                    .frame(width: 8, height: 8)
            }
            .padding(.leading, 6)
            .padding(.trailing, DS.Space.md)
            .frame(minHeight: 36)
            .background(DS.Palette.canvas, in: .capsule)
            .fixedSize()
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(PressScaleStyle(scale: 0.94))
        .accessibilityLabel(unlocked ? "\(likers.count) people like you. See who"
                                     : "\(likers.count) people like you. Unlock with drafft tempo")
    }
}
