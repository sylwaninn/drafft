import SwiftUI
import UIKit

/// An empty tab's sign as a sticker: the tab's icon filled (its Solar bold twin) on a white die-cut
/// edge, slightly tilted, its top-right corner never quite stuck. Arriving on the screen after a
/// while shows the last of it being pressed down; switching tabs back and forth doesn't replay it.
/// The loose corner follows the finger a little and springs back.
struct EmptyStateSticker: View {
    let art: EmptyStateArt
    @Environment(\.tabsOnScreen) private var onScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0: still half peeled (the pose the arrival starts from), 1: pressed down, corner at rest.
    @State private var stuck: CGFloat
    @State private var shown = false
    @GestureState(resetTransaction: Transaction(animation: Motion.bouncy)) private var pull: CGSize = .zero

    static let side: CGFloat = 116
    private static let tilt = Angle.degrees(-6)
    /// How far the fold sits inside the sticker's edge, at rest and when the arrival starts.
    private static let restPeel: CGFloat = 11
    private static let arrivalPeel: CGFloat = 46
    /// The farthest the finger can move the corner (rubber-banded on the way).
    private static let maxPull: CGFloat = 24
    private static let arrival = Animation.spring(response: 0.42, dampingFraction: 0.74)

    init(art: EmptyStateArt) {
        self.art = art
        _stuck = State(initialValue: StickerVisits.isDue(art.symbol) ? 0 : 1)
    }

    var body: some View {
        let sheet = StickerSheet.make(art.symbol, side: Self.side)
        PeeledSticker(sheet: sheet, side: Self.side, corner: corner(reach: sheet.reach))
            .scaleEffect(1 + 0.06 * (1 - stuck))
            .rotationEffect(Self.tilt)
            .frame(width: Self.side + 12, height: Self.side + 12)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .updating($pull) { value, state, _ in state = value.translation }
            )
            .onChange(of: pull == .zero) { _, released in
                if !released { Haptics.select() }
            }
            .onAppear {
                shown = true
                if onScreen { arrive() }
            }
            .onChange(of: onScreen) { _, now in
                if now && shown { arrive() }
            }
            .onDisappear {
                shown = false
                if onScreen { StickerVisits.leave(art.symbol) }
            }
            .accessibilityHidden(true)
    }

    /// Where the loose corner sits, from the top-right corner of the sticker: on the diagonal, as
    /// deep as the arrival or the rest wants, then wherever the finger takes it.
    private func corner(reach: CGFloat) -> CGVector {
        let inward = CGVector(dx: -1 / 2.squareRoot(), dy: 1 / 2.squareRoot())
        let depth = Self.arrivalPeel + (Self.restPeel - Self.arrivalPeel) * stuck
        // The fold is halfway between the corner and where the corner lands.
        let length = 2 * (reach + depth)
        var v = CGVector(dx: inward.dx * length, dy: inward.dy * length)
        let finger = hypot(pull.width, pull.height)
        if finger > 0 {
            let k = Self.maxPull / (finger + Self.maxPull)
            // The finger moves on screen; the sticker is tilted.
            let a = -Self.tilt.radians
            let x = pull.width * k, y = pull.height * k
            v.dx += x * cos(a) - y * sin(a)
            v.dy += x * sin(a) + y * cos(a)
        }
        // Pushed back toward its corner, it stays a little loose.
        let along = v.dx * inward.dx + v.dy * inward.dy
        let least = 2 * (reach + 3)
        if along < least {
            v.dx += inward.dx * (least - along)
            v.dy += inward.dy * (least - along)
        }
        return v
    }

    private func arrive() {
        guard StickerVisits.isDue(art.symbol), !reduceMotion else {
            stuck = 1
            return
        }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { stuck = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(Self.arrival) { stuck = 1 }
        }
        StickerVisits.leave(art.symbol)
    }
}

/// When each sticker was last left, so a quick round of tabs doesn't replay its arrival.
@MainActor
enum StickerVisits {
    /// Away at least this long (seconds) and the sticker is pressed down again on the way back.
    static let replayAfter: TimeInterval = 30
    private static var left: [String: Date] = [:]

    static func isDue(_ key: String) -> Bool {
        guard let date = left[key] else { return true }
        return Date().timeIntervalSince(date) > replayAfter
    }

    static func leave(_ key: String) { left[key] = Date() }
}

/// The sticker, its corner folded back along the line halfway between the top-right corner and
/// `corner` (paper folding): the front is cut along that line, the part beyond it shows its back,
/// mirrored over the sticker.
private struct PeeledSticker: View, Animatable {
    let sheet: StickerSheet
    let side: CGFloat
    var corner: CGVector

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(corner.dx, corner.dy) }
        set { corner = CGVector(dx: newValue.first, dy: newValue.second) }
    }

    var body: some View {
        let length = max(hypot(corner.dx, corner.dy), 0.001)
        let normal = CGVector(dx: corner.dx / length, dy: corner.dy / length)
        let fold = CGPoint(x: side + corner.dx / 2, y: corner.dy / 2)
        ZStack {
            Image(uiImage: sheet.front)
                .resizable()
                .mask { HalfPlane(point: fold, normal: normal) }
                .compositingGroup()
                .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
            Image(uiImage: sheet.back)
                .resizable()
                .mask { HalfPlane(point: fold, normal: CGVector(dx: -normal.dx, dy: -normal.dy)) }
                .transformEffect(Self.mirror(through: fold, normal: normal))
                .compositingGroup()
                .shadow(color: .black.opacity(0.2), radius: 2.5, x: -1, y: 2)
        }
        .frame(width: side, height: side)
    }

    /// Reflection across the line through `point` perpendicular to `normal` (a unit vector).
    private static func mirror(through point: CGPoint, normal n: CGVector) -> CGAffineTransform {
        let offset = 2 * (point.x * n.dx + point.y * n.dy)
        return CGAffineTransform(a: 1 - 2 * n.dx * n.dx, b: -2 * n.dx * n.dy,
                                 c: -2 * n.dx * n.dy, d: 1 - 2 * n.dy * n.dy,
                                 tx: offset * n.dx, ty: offset * n.dy)
    }
}

/// Everything on the side of the line through `point` that `normal` points to.
private struct HalfPlane: Shape {
    let point: CGPoint
    let normal: CGVector

    func path(in rect: CGRect) -> Path {
        let far: CGFloat = 4 * max(rect.width, rect.height, 1)
        let along = CGVector(dx: -normal.dy, dy: normal.dx)
        func at(_ s: CGFloat, _ t: CGFloat) -> CGPoint {
            CGPoint(x: point.x + along.dx * s + normal.dx * t, y: point.y + along.dy * s + normal.dy * t)
        }
        var path = Path()
        path.addLines([at(-far, 0), at(far, 0), at(far, far), at(-far, far)])
        path.closeSubpath()
        return path
    }
}

/// A sticker's two faces, drawn once per sign: the front (white die-cut edge around the filled
/// sign) and the back (the same outline in grey). `reach` is how far the outline sits from the
/// square's top-right corner, measured along the diagonal: where a fold starts to catch paper.
@MainActor
struct StickerSheet {
    let front: UIImage
    let back: UIImage
    let reach: CGFloat

    private static var cache: [String: StickerSheet] = [:]
    private static let edge: CGFloat = 7

    static func make(_ symbol: String, side: CGFloat) -> StickerSheet {
        if let sheet = cache[symbol] { return sheet }
        let size = CGSize(width: side, height: side)
        let inset = edge + 3
        let box = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        let glyph = UIImage(named: "\(symbol)-bold") ?? UIImage(named: symbol) ?? UIImage()
        let fit = fitted(glyph.size, in: box)
        let paper = UIColor(DS.Palette.stickerPaper)
        let ink = UIColor(DS.Palette.stickerInk)
        let backColor = UIColor(DS.Palette.stickerBack)

        // The die cut: the sign spread out by `edge` in every direction (rings of copies, close
        // enough that thin strokes leave no gap), which also fills its small holes.
        func outline(_ color: UIColor) {
            let tinted = glyph.withTintColor(color, renderingMode: .alwaysOriginal)
            tinted.draw(in: fit)
            for ring in 1...3 {
                let r = edge * CGFloat(ring) / 3
                for step in 0..<32 {
                    let a = CGFloat(step) / 32 * 2 * .pi
                    tinted.draw(in: fit.offsetBy(dx: r * cos(a), dy: r * sin(a)))
                }
            }
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        let front = renderer.image { _ in
            outline(paper)
            glyph.withTintColor(ink, renderingMode: .alwaysOriginal).draw(in: fit)
        }
        let back = renderer.image { _ in outline(backColor) }
        let sheet = StickerSheet(front: front, back: back, reach: reach(of: back, side: side))
        cache[symbol] = sheet
        return sheet
    }

    private static func fitted(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return box }
        let k = min(box.width / size.width, box.height / size.height)
        let w = size.width * k, h = size.height * k
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    /// The nearest opaque pixel to the top-right corner, along the diagonal, in points.
    private static func reach(of image: UIImage, side: CGFloat) -> CGFloat {
        guard let cg = image.cgImage else { return side * 0.2 }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return side * 0.2 }
        var nearest = CGFloat.greatestFiniteMagnitude
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 128 {
                nearest = min(nearest, CGFloat(w - x + y))
            }
        }
        guard nearest < .greatestFiniteMagnitude else { return side * 0.2 }
        return nearest / 2.squareRoot() * side / CGFloat(w)
    }
}
