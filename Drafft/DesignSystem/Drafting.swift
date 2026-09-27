import SwiftUI

// The drafting motif from the app icon: a lead shape followed by fading ghost copies,
// like riders tucked in behind each other. On the profile it is used under buttons only.

extension View {
    /// Draws `count` fading copies of `shape` behind the view, each shifted by `step`.
    func draftTrail<S: Shape>(_ shape: S, color: Color = DS.Palette.lime, count: Int = 2,
                              step: CGSize = CGSize(width: -7, height: 0)) -> some View {
        background {
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

/// Deterministic pseudo-random numbers from a string seed.
struct SeededRandom {
    private var h: UInt64
    init(_ seed: String) {
        var h: UInt64 = 1469598103934665603
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        self.h = h
    }
    mutating func next() -> CGFloat {
        h = h &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((h >> 33) % 10_000) / 10_000
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() * CGFloat(range.count)) % range.count
    }
}

/// Topographic contour lines, like a trail map. A small terrain is generated (a main summit near an
/// edge of the block, a few secondary hills and ridges, plus gentle noise), then iso-lines are traced on
/// it with marching squares. Spacing, merges and splits come from the terrain, so it reads as real relief.
struct ContourLines: View {
    let seed: String
    var tint: Color

    /// Each block type has one fixed composition: where the main summit sits, and how busy the map is.
    private struct Style { var summit: UnitPoint; var hills: Int; var levels: Int }
    private static let styles: [String: Style] = [
        BackdropSeed.voice: Style(summit: UnitPoint(x: 0.92, y: 0.05), hills: 3, levels: 13),
        BackdropSeed.icebreaker: Style(summit: UnitPoint(x: 0.9, y: 0.95), hills: 4, levels: 13),
        BackdropSeed.goal: Style(summit: UnitPoint(x: 0.85, y: 0.2), hills: 3, levels: 12),
        BackdropSeed.sport: Style(summit: UnitPoint(x: 0.95, y: 0.4), hills: 4, levels: 14),
        BackdropSeed.session: Style(summit: UnitPoint(x: 0.9, y: 0.1), hills: 3, levels: 12),
        BackdropSeed.me: Style(summit: UnitPoint(x: 0.85, y: 0.05), hills: 3, levels: 13),
        BackdropSeed.deckEmpty: Style(summit: UnitPoint(x: 0.5, y: 0.5), hills: 3, levels: 13),
        BackdropSeed.nextSession: Style(summit: UnitPoint(x: 0.9, y: 0.1), hills: 3, levels: 13)
    ]

    /// Terrain version per block type. All validated and FROZEN: don't change these values
    /// (a new block type gets its own entry; existing ones never get redrawn).
    private static let terrainVersions: [String: String] = [
        BackdropSeed.goal: "relief-4",
        BackdropSeed.sport: "relief-4",
        BackdropSeed.voice: "relief-5",
        BackdropSeed.icebreaker: "relief-5",
        BackdropSeed.session: "relief-5",
        BackdropSeed.me: "relief-5",
        BackdropSeed.deckEmpty: "relief-5",
        BackdropSeed.nextSession: "relief-5"
    ]

    /// Terrain is laid out on a fixed reference frame so it never shifts when a block grows.
    private static let refSize = CGSize(width: 360, height: 260)

    private struct Hill { var x, y, rx, ry, h, angle: Double }

    var body: some View {
        Canvas { ctx, size in
            for line in Self.lines(seed: seed, size: size) {
                ctx.stroke(line.path, with: .color(tint.opacity(line.index ? 0.3 : 0.15)),
                           style: StrokeStyle(lineWidth: line.index ? 1.2 : 0.8, lineCap: .round, lineJoin: .round))
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    struct Line { let path: Path; let index: Bool }

    /// Traced lines per block type and size. The terrain is frozen, so the tracing is done once and
    /// reused: a block that re-renders (state change, animation frame, pushed screen) only strokes.
    nonisolated(unsafe) private static var cache: [String: [Line]] = [:]
    private static let lock = NSLock()

    static func lines(seed: String, size: CGSize) -> [Line] {
        let key = "\(seed)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let traced = trace(seed: seed, size: size)
        cache[key] = traced
        return traced
    }

    private static func trace(seed: String, size: CGSize) -> [Line] {
        let style = styles[seed] ?? Style(summit: .topTrailing, hills: 4, levels: 16)
        var out: [Line] = []
        var rng = SeededRandom("\(seed)-\(terrainVersions[seed] ?? "relief-5")")
        let W = Double(refSize.width), H = Double(refSize.height)

        // Main summit near the style's anchor, then secondary hills spread around it.
        var hills = [Hill(x: Double(style.summit.x) * W, y: Double(style.summit.y) * H,
                          rx: 190 + Double(rng.next()) * 80, ry: 140 + Double(rng.next()) * 60,
                          h: 1.0, angle: Double(rng.next()) * .pi)]
        for _ in 0..<style.hills {
            hills.append(Hill(x: Double(rng.next()) * W * 1.2 - W * 0.1,
                              y: Double(rng.next()) * H * 1.2 - H * 0.1,
                              rx: 80 + Double(rng.next()) * 110, ry: 60 + Double(rng.next()) * 80,
                              h: 0.15 + Double(rng.next()) * 0.3, angle: Double(rng.next()) * .pi))
        }
        // Low-frequency undulation so slopes aren't perfectly smooth.
        let waves = (0..<3).map { _ in (a: Double(rng.next()) * .pi * 2, f: 0.012 + Double(rng.next()) * 0.02,
                                        p: Double(rng.next()) * .pi * 2) }

        func height(_ x: Double, _ y: Double) -> Double {
            var z = 0.0
            for hl in hills {
                let dx = x - hl.x, dy = y - hl.y
                let u = dx * cos(hl.angle) + dy * sin(hl.angle)
                let v = -dx * sin(hl.angle) + dy * cos(hl.angle)
                z += hl.h * exp(-(u * u) / (2 * hl.rx * hl.rx) - (v * v) / (2 * hl.ry * hl.ry))
            }
            for w in waves {
                z += 0.02 * sin((x * cos(w.a) + y * sin(w.a)) * w.f + w.p)
            }
            return z
        }

        // Sample the terrain on a grid covering the visible block (in reference units).
        let cell = 5.0
        let scale = W / Double(max(size.width, 1))
        let cols = Int(Double(size.width) * scale / cell) + 2
        let rows = Int(Double(size.height) * scale / cell) + 2
        var grid = [Double](repeating: 0, count: cols * rows)
        var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
        for r in 0..<rows { for c in 0..<cols {
            let z = height(Double(c) * cell, Double(r) * cell)
            grid[r * cols + c] = z
            lo = min(lo, z); hi = max(hi, z)
        } }
        let toView = CGFloat(1 / scale)

        // Marching squares, one path per level; every fifth level is an index contour.
        for li in 1...style.levels {
            let level = lo + (hi - lo) * Double(li) / Double(style.levels + 1)
            var path = Path()
            for r in 0..<(rows - 1) { for c in 0..<(cols - 1) {
                let v0 = grid[r * cols + c], v1 = grid[r * cols + c + 1]
                let v2 = grid[(r + 1) * cols + c + 1], v3 = grid[(r + 1) * cols + c]
                var idx = 0
                if v0 > level { idx |= 8 }; if v1 > level { idx |= 4 }
                if v2 > level { idx |= 2 }; if v3 > level { idx |= 1 }
                if idx == 0 || idx == 15 { continue }
                let x = Double(c) * cell, y = Double(r) * cell
                func lerp(_ a: Double, _ b: Double) -> Double { (level - a) / (b - a) }
                let top = CGPoint(x: (x + cell * lerp(v0, v1)) * toView, y: y * toView)
                let right = CGPoint(x: (x + cell) * toView, y: (y + cell * lerp(v1, v2)) * toView)
                let bottom = CGPoint(x: (x + cell * lerp(v3, v2)) * toView, y: (y + cell) * toView)
                let left = CGPoint(x: x * toView, y: (y + cell * lerp(v0, v3)) * toView)
                func seg(_ a: CGPoint, _ b: CGPoint) { path.move(to: a); path.addLine(to: b) }
                switch idx {
                case 1, 14: seg(left, bottom)
                case 2, 13: seg(bottom, right)
                case 3, 12: seg(left, right)
                case 4, 11: seg(top, right)
                case 5: seg(left, top); seg(bottom, right)
                case 6, 9: seg(top, bottom)
                case 7, 8: seg(left, top)
                case 10: seg(left, bottom); seg(top, right)
                default: break
                }
            } }
            out.append(Line(path: path, index: li % 5 == 0))
        }
        return out
    }
}

extension View {
    /// Rounded coloured block with a contour-line texture behind its content.
    func draftBlock(_ fill: Color, seed: String, tint: Color, radius: CGFloat = DS.Radius.xl) -> some View {
        background {
            fill.overlay { ContourLines(seed: seed, tint: tint) }
                .clipShape(.rect(cornerRadius: radius))
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(DS.Palette.blockEdge, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

/// Block types with a texture: one fixed design each, identical on every profile.
/// Changing a value changes that block's design everywhere, so only do it on purpose.
enum BackdropSeed {
    static let voice = "voice"
    static let icebreaker = "icebreaker"
    static let goal = "goal"
    static let session = "session"
    static let deckEmpty = "too-tight" // Discover's empty stack; value kept, the terrain is frozen
    static let me = "me"
    static let nextSession = "next-session"
    static let sport = "sport"
    /// Log-in page background. FROZEN by the user: never change this value, nor the
    /// `TerrainField` generator it runs through.
    static let login = "login-2"
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

/// Full-page background for sign-up and log-in: the sage page with the contour texture, faint.
/// Each seed is a different terrain. When the seed changes, the terrain itself morphs into the
/// next one: the lines slide and reshape continuously (no fade).
struct PageContourBackdrop: View {
    let seed: String

    @State private var from: String = ""
    @State private var to: String = ""
    @State private var progress: Double = 1

    var body: some View {
        ZStack {
            Rectangle().fill(DS.Palette.canvasSoft)
            if !to.isEmpty {
                MorphingContours(from: TerrainField(seed: from.isEmpty ? to : from),
                                 to: TerrainField(seed: to), progress: progress, tint: DS.Palette.ink)
                    .opacity(0.5)
            }
        }
        .ignoresSafeArea()
        .onAppear { if to.isEmpty { from = seed; to = seed; progress = 1 } }
        .onChange(of: seed) { old, new in
            var t = Transaction(animation: nil)
            t.disablesAnimations = true
            withTransaction(t) { from = to.isEmpty ? old : to; to = new; progress = 0 }
            withAnimation(.easeInOut(duration: 0.9)) { progress = 1 }
        }
        .accessibilityHidden(true)
    }
}

/// A seeded terrain (summit, hills, gentle waves), heights normalised to 0...1 over the frame.
/// FROZEN: the log-in background (`BackdropSeed.login`) was validated on this exact generator.
/// Don't change the maths or the "-relief-5" suffix; add a new generator instead.
struct TerrainField: Equatable {
    private struct Hill: Equatable { var x, y, rx, ry, h, angle: Double }
    private var hills: [Hill] = []
    private var waves: [(a: Double, f: Double, p: Double)] = []
    let seed: String

    static func == (l: TerrainField, r: TerrainField) -> Bool { l.seed == r.seed }

    init(seed: String) {
        self.seed = seed
        var rng = SeededRandom("\(seed)-relief-5")
        let W = 360.0, H = 780.0
        hills = [Hill(x: (0.55 + Double(rng.next()) * 0.4) * W, y: Double(rng.next()) * H,
                      rx: 190 + Double(rng.next()) * 80, ry: 160 + Double(rng.next()) * 80,
                      h: 1, angle: Double(rng.next()) * .pi)]
        for _ in 0..<5 {
            hills.append(Hill(x: Double(rng.next()) * W * 1.2 - W * 0.1, y: Double(rng.next()) * H * 1.1 - H * 0.05,
                              rx: 80 + Double(rng.next()) * 110, ry: 60 + Double(rng.next()) * 90,
                              h: 0.15 + Double(rng.next()) * 0.35, angle: Double(rng.next()) * .pi))
        }
        waves = (0..<3).map { _ in (a: Double(rng.next()) * .pi * 2, f: 0.012 + Double(rng.next()) * 0.02,
                                    p: Double(rng.next()) * .pi * 2) }
    }

    func height(_ x: Double, _ y: Double) -> Double {
        var z = 0.0
        for hl in hills {
            let dx = x - hl.x, dy = y - hl.y
            let u = dx * cos(hl.angle) + dy * sin(hl.angle)
            let v = -dx * sin(hl.angle) + dy * cos(hl.angle)
            z += hl.h * exp(-(u * u) / (2 * hl.rx * hl.rx) - (v * v) / (2 * hl.ry * hl.ry))
        }
        for w in waves { z += 0.02 * sin((x * cos(w.a) + y * sin(w.a)) * w.f + w.p) }
        return z
    }
}

/// Contour lines of a blend between two terrains; `progress` is animatable, so the map morphs.
struct MorphingContours: View, Animatable {
    let from: TerrainField
    let to: TerrainField
    var progress: Double
    var tint: Color
    var levels = 16
    /// Multiplies the lines' opacity (15 % and 30 % for index lines): above 1 on a night page.
    var strength = 1.0

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            for line in Self.lines(from: from, to: to, progress: progress, size: size, levels: levels) {
                ctx.stroke(line.path, with: .color(tint.opacity(min(1, (line.index ? 0.3 : 0.15) * strength))),
                           style: StrokeStyle(lineWidth: line.index ? 1.2 : 0.8, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension MorphingContours {
    private static let cell = 7.0

    /// Normalised samples per terrain and grid, and traced lines for terrains at rest: computed
    /// once, so the page behind a form doesn't re-trace its map on every keystroke. Only the
    /// 0.9 s morph between steps traces per frame, from cached samples.
    nonisolated(unsafe) private static var samples: [String: [Double]] = [:]
    nonisolated(unsafe) private static var rest: [String: [ContourLines.Line]] = [:]
    private static let lock = NSLock()

    static func lines(from: TerrainField, to: TerrainField, progress: Double, size: CGSize,
                      levels: Int) -> [ContourLines.Line] {
        let W = 360.0
        let scale = W / Double(max(size.width, 1))
        let cols = Int(Double(size.width) * scale / cell) + 2
        let rows = Int(Double(size.height) * scale / cell) + 2
        let t = min(1, max(0, progress))
        let atRest = t >= 1 || from == to
        let restKey = "\(to.seed)|\(cols)x\(rows)|\(levels)"

        lock.lock(); defer { lock.unlock() }
        if atRest, let hit = rest[restKey] { return hit }

        func sample(_ f: TerrainField) -> [Double] {
            let key = "\(f.seed)|\(cols)x\(rows)"
            if let hit = samples[key] { return hit }
            var g = [Double](repeating: 0, count: cols * rows)
            var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
            for r in 0..<rows { for c in 0..<cols {
                let z = f.height(Double(c) * cell, Double(r) * cell)
                g[r * cols + c] = z; lo = min(lo, z); hi = max(hi, z)
            } }
            let span = max(hi - lo, 0.0001)
            let n = g.map { ($0 - lo) / span }
            samples[key] = n
            return n
        }
        // Each terrain normalised to 0...1, then blended: levels stay comparable mid-morph.
        let grid: [Double] = atRest ? sample(to) : zip(sample(from), sample(to)).map { $0 * (1 - t) + $1 * t }
        let toView = CGFloat(1 / scale)

        var out: [ContourLines.Line] = []
        for li in 1...levels {
            let level = Double(li) / Double(levels + 1)
            var path = Path()
            for r in 0..<(rows - 1) { for c in 0..<(cols - 1) {
                let v0 = grid[r * cols + c], v1 = grid[r * cols + c + 1]
                let v2 = grid[(r + 1) * cols + c + 1], v3 = grid[(r + 1) * cols + c]
                var idx = 0
                if v0 > level { idx |= 8 }; if v1 > level { idx |= 4 }
                if v2 > level { idx |= 2 }; if v3 > level { idx |= 1 }
                if idx == 0 || idx == 15 { continue }
                let x = Double(c) * cell, y = Double(r) * cell
                func lerp(_ p: Double, _ q: Double) -> Double { (level - p) / (q - p) }
                let top = CGPoint(x: (x + cell * lerp(v0, v1)) * toView, y: y * toView)
                let right = CGPoint(x: (x + cell) * toView, y: (y + cell * lerp(v1, v2)) * toView)
                let bottom = CGPoint(x: (x + cell * lerp(v3, v2)) * toView, y: (y + cell) * toView)
                let left = CGPoint(x: x * toView, y: (y + cell * lerp(v0, v3)) * toView)
                func seg(_ p: CGPoint, _ q: CGPoint) { path.move(to: p); path.addLine(to: q) }
                switch idx {
                case 1, 14: seg(left, bottom)
                case 2, 13: seg(bottom, right)
                case 3, 12: seg(left, right)
                case 4, 11: seg(top, right)
                case 5: seg(left, top); seg(bottom, right)
                case 6, 9: seg(top, bottom)
                case 7, 8: seg(left, top)
                case 10: seg(left, bottom); seg(top, right)
                default: break
                }
            } }
            out.append(ContourLines.Line(path: path, index: li % 5 == 0))
        }
        if atRest { rest[restKey] = out }
        return out
    }
}
