import SwiftUI

// The drafting motif: a lead shape followed by fading ghost copies, like riders tucked in
// behind each other. Under buttons only, never under the logo (Wordmark).

extension View {
    /// Draws `count` fading copies of `shape` behind the view, each shifted by `step`.
    /// With no `color`, the trail takes the accent of the surface it sits on.
    func draftTrail<S: Shape>(_ shape: S, color: Color? = nil, count: Int = 2,
                              step: CGSize = CGSize(width: -7, height: 0)) -> some View {
        modifier(DraftTrail(shape: shape, color: color, count: count, step: step))
    }
}

private struct DraftTrail<S: Shape>: ViewModifier {
    let shape: S
    let color: Color?
    let count: Int
    let step: CGSize
    @Environment(\.isNightSurface) private var onNight

    func body(content: Content) -> some View {
        let color = color ?? (onNight ? DS.Palette.accentOnNight : DS.Palette.lime)
        return content.background {
            ZStack {
                ForEach((1...max(count, 1)).reversed(), id: \.self) { i in
                    shape
                        .fill(color.opacity(i == 1 ? 0.55 : 0.25))
                        .offset(x: step.width * CGFloat(i), y: step.height * CGFloat(i))
                }
            }
            // Decoration only: the ghosts reach past the button and must not eat taps there.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// A night block: the rounded night fill, with its content marked as on night.
    func nightBlock(radius: CGFloat = DS.Radius.xl) -> some View {
        nightSurface().draftBlock(DS.Palette.night, radius: radius)
    }
}

/// Round icon badge carrying a bold SF Symbol. No trail: the drafting effect is reserved for buttons.
struct DraftGlyph: View {
    let symbol: String
    var size: CGFloat = 48
    var fill: AnyShapeStyle = AnyShapeStyle(DS.Palette.lime)
    var glyph: Color = DS.Palette.onLime

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.38, weight: .bold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(glyph)
            .frame(width: size, height: size)
            .background(fill, in: .circle)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Rounded coloured block behind its content.
    func draftBlock(_ fill: Color, radius: CGFloat = DS.Radius.xl) -> some View {
        background { fill.clipShape(.rect(cornerRadius: radius)) }
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(DS.Palette.blockEdge, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

/// The drafft tempo mark: a "+" drawn as a four-point spark, stretched wide.
struct SparkPlus: Shape {
    /// How pinched the sides are: 0 = sharp star, 1 = diamond.
    var pinch: CGFloat = 0.16

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let top = CGPoint(x: c.x, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: c.y)
        let bottom = CGPoint(x: c.x, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: c.y)
        let dx = rect.width / 2 * pinch, dy = rect.height / 2 * pinch
        var p = Path()
        p.move(to: top)
        p.addQuadCurve(to: right, control: CGPoint(x: c.x + dx, y: c.y - dy))
        p.addQuadCurve(to: bottom, control: CGPoint(x: c.x + dx, y: c.y + dy))
        p.addQuadCurve(to: left, control: CGPoint(x: c.x - dx, y: c.y + dy))
        p.addQuadCurve(to: top, control: CGPoint(x: c.x - dx, y: c.y - dy))
        p.closeSubpath()
        return p
    }
}

/// Super like mark: a heart drafting forward, with fading ghost hearts behind it.
/// The one icon allowed to carry the drafting trail (user request).
struct SuperLikeMark: View {
    var size: CGFloat = 20
    var color: Color = DS.Palette.lime

    var body: some View {
        ZStack {
            ForEach([2, 1], id: \.self) { i in
                heart.foregroundStyle(color.opacity(i == 1 ? 0.55 : 0.25))
                    .offset(x: -size * 0.24 * CGFloat(i))
            }
            heart.foregroundStyle(color)
        }
        .padding(.leading, size * 0.48)
        .accessibilityHidden(true)
    }

    private var heart: some View {
        Image(systemName: "heart.fill").font(.system(size: size, weight: .heavy))
    }
}

/// Round super-like button face: the mark with what's left written under it, both inside the
/// disc (a count never hangs off a button's edge). No number at zero.
struct SuperLikeCountMark: View {
    let count: Int
    var size: CGFloat = 52

    var body: some View {
        VStack(spacing: 1) {
            SuperLikeMark(size: size * 0.3, color: .white)
                .offset(x: -size * 0.07)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: size * 0.21, weight: .heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .transition(.opacity)
            }
        }
        .offset(y: count > 0 ? size * 0.02 : 0)
        .frame(width: size, height: size)
        .background(DS.Palette.negative, in: .circle)
        .animation(Motion.snappy, value: count)
    }
}
