import SwiftUI

/// Launch: it starts on the launch screen's exact frame (page tone, the word in violet centred,
/// `LaunchMark`), and a contour map unfolds from its summit with a soft
/// edge, settling as it forms (a 3 % zoom easing out). Its speed follows the launch through a
/// critically damped spring: it heads for 85 % while loading, then for 100 % once the app is ready,
/// with no step in between; then the splash fades onto the first screen. It never waits longer than
/// the launch itself.
struct SplashView: View {
    /// True once the first screen is ready (tabs mounted, session restored).
    let isReady: Bool
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var start = Date.now
    @State private var readyAt: Date?
    @State private var fading = false
    @State private var map: SplashRelief.Map?
    /// Spring state, advanced once per frame: a reference, so a frame never writes view state.
    @State private var spring = Spring()

    var body: some View {
        ZStack {
            Rectangle().fill(DS.Palette.canvasSoft)
            GeometryReader { geo in
                if let map {
                    TimelineView(.animation(paused: fading)) { context in
                        let p = spring.step(to: target(at: context.date), at: context.date, instant: reduceMotion)
                        relief(map, size: geo.size, progress: p)
                            .onChange(of: readyAt != nil && spring.settled) { _, done in if done { finish() } }
                    }
                }
            }
            mark
        }
        .ignoresSafeArea()
        .opacity(fading ? 0 : 1)
        .allowsHitTesting(!fading)
        .accessibilityHidden(true)
        .task {
            start = .now
            if isReady { readyAt = .now }
            let size = UIScreen.main.bounds.size
            map = await Task.detached(priority: .userInitiated) { SplashRelief.map(size: size) }.value
        }
        .onChange(of: isReady) { _, ready in if ready, readyAt == nil { readyAt = .now } }
    }

    private func relief(_ map: SplashRelief.Map, size: CGSize, progress p: Double) -> some View {
        let summit = UnitPoint(x: map.summit.x / max(size.width, 1), y: map.summit.y / max(size.height, 1))
        let far = map.reach * 1.15
        let radius = max(1, p * far)
        // On the dark page the lines take a lighter violet and a little more weight, to read as faintly.
        let dark = scheme == .dark
        let line = dark ? DS.Palette.limeNeutral : DS.Palette.lime
        let opacity = dark ? (thin: 0.2, index: 0.4) : (thin: 0.16, index: 0.34)
        return Canvas { ctx, _ in
            for level in map.levels {
                ctx.stroke(level.path, with: .color(line.opacity(level.index ? opacity.index : opacity.thin)),
                           style: StrokeStyle(lineWidth: level.index ? 1.2 : 0.75, lineCap: .round, lineJoin: .round))
            }
        }
        .scaleEffect(1 + 0.03 * (1 - min(1, p)), anchor: summit)
        .mask {
            // design-lint: allow gradient - a mask: the map unfolds from its summit with a soft edge
            RadialGradient(colors: [.black, .clear], center: summit,
                           startRadius: radius * 0.55, endRadius: radius)
        }
    }

    /// The word from the launch screen, in violet (a lighter violet on the dark page).
    private var mark: some View { Image("LaunchMark") }

    /// Where the map heads: toward 85 % while loading, all of it once ready.
    private func target(at date: Date) -> Double {
        readyAt == nil ? 0.85 * (1 - exp(-date.timeIntervalSince(start) / 0.9)) : 1
    }

    private func finish() {
        guard !fading else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.3)) { fading = true } completion: { onFinished() }
        }
    }

    /// A critically damped spring (ω 7): smooth whatever the target does.
    final class Spring {
        private(set) var value = 0.0
        private var velocity = 0.0
        private var last: Date?
        var settled: Bool { value > 0.995 && abs(velocity) < 0.02 }

        func step(to target: Double, at date: Date, instant: Bool) -> Double {
            defer { last = date }
            if instant { value = target; velocity = 0; return value }
            let dt = min(0.05, date.timeIntervalSince(last ?? date))
            let omega = 7.0
            velocity += (omega * omega * (target - value) - 2 * omega * velocity) * dt
            value += velocity * dt
            return value
        }
    }
}

/// The splash's terrain: a main massif upper right and a lower hill bottom left, over gentle fractal
/// ground with soft ridges and a light warp, traced as 22 contour lines (every fifth an index line).
/// Its own generator: the frozen block and log-in terrains (`TerrainField`, `ContourLines`) are untouched.
enum SplashRelief {
    struct Level { let path: Path; let index: Bool }
    struct Map {
        let levels: [Level]
        let summit: CGPoint
        /// Distance from the summit to the farthest corner.
        let reach: CGFloat
    }

    static func map(size: CGSize) -> Map {
        let w = Double(size.width), h = Double(size.height), cell = 3.0
        let ground = Noise(seed: 20_260_926), rock = Noise(seed: 771)
        func fbm(_ x: Double, _ y: Double, _ octaves: Int) -> Double {
            var sum = 0.0, freq = 1.0, amp = 1.0, total = 0.0
            for _ in 0..<octaves { sum += amp * ground.at(x * freq, y * freq); total += amp; freq *= 2.03; amp *= 0.45 }
            return sum / total
        }
        func ridge(_ x: Double, _ y: Double) -> Double {
            var sum = 0.0, freq = 1.0, amp = 0.6
            for _ in 0..<4 { sum += amp * (1 - abs(rock.at(x * freq, y * freq))); freq *= 2.1; amp *= 0.5 }
            return sum
        }
        func height(_ x: Double, _ y: Double) -> Double {
            var u = x / w, v = y / w
            let wx = fbm(u * 2.2 + 3.1, v * 2.2, 3), wy = fbm(u * 2.2, v * 2.2 + 7.7, 3)
            u += 0.12 * wx; v += 0.12 * wy
            let dx = (u - 0.74) / 0.42, dy = (v * w / h * 1.9 - 0.36) / 0.5
            let dx2 = (u - 0.18) / 0.3, dy2 = (v * w / h * 1.9 - 1.45) / 0.35
            return 1.3 * exp(-(dx * dx + dy * dy)) + 0.45 * exp(-(dx2 * dx2 + dy2 * dy2))
                + 0.5 * fbm(u * 2.2, v * 2.2, 4) + 0.12 * ridge(u * 2.6, v * 2.6)
        }

        let cols = Int(w / cell) + 2, rows = Int(h / cell) + 2
        var grid = [Double](repeating: 0, count: cols * rows)
        var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
        var summit = CGPoint.zero
        for r in 0..<rows { for c in 0..<cols {
            let z = height(Double(c) * cell, Double(r) * cell)
            grid[r * cols + c] = z
            lo = min(lo, z)
            if z > hi { hi = z; summit = CGPoint(x: Double(c) * cell, y: Double(r) * cell) }
        } }

        let count = 22
        let levels = (1...count).map { li in
            Level(path: contour(at: lo + (hi - lo) * Double(li) / Double(count + 1), grid: grid, cols: cols, rows: rows, cell: cell),
                  index: li.isMultiple(of: 5))
        }
        let reach = [CGPoint.zero, CGPoint(x: w, y: 0), CGPoint(x: 0, y: h), CGPoint(x: w, y: h)]
            .map { hypot($0.x - summit.x, $0.y - summit.y) }.max() ?? w
        return Map(levels: levels, summit: summit, reach: reach)
    }

    /// Which cell edges a contour joins, per marching-squares case (0 top, 1 right, 2 bottom, 3 left).
    private static let cases: [Int: [(Int, Int)]] = [
        1: [(3, 2)], 14: [(3, 2)], 2: [(2, 1)], 13: [(2, 1)], 3: [(3, 1)], 12: [(3, 1)],
        4: [(0, 1)], 11: [(0, 1)], 6: [(0, 2)], 9: [(0, 2)], 7: [(3, 0)], 8: [(3, 0)],
        5: [(3, 0), (2, 1)], 10: [(3, 2), (0, 1)]
    ]

    /// One contour line over the sampled grid (marching squares).
    private static func contour(at level: Double, grid: [Double], cols: Int, rows: Int, cell: Double) -> Path {
        var path = Path()
        for r in 0..<(rows - 1) { for c in 0..<(cols - 1) {
            let v0 = grid[r * cols + c], v1 = grid[r * cols + c + 1]
            let v2 = grid[(r + 1) * cols + c + 1], v3 = grid[(r + 1) * cols + c]
            let idx = (v0 > level ? 8 : 0) | (v1 > level ? 4 : 0) | (v2 > level ? 2 : 0) | (v3 > level ? 1 : 0)
            guard let joins = cases[idx] else { continue }
            let x = Double(c) * cell, y = Double(r) * cell
            func lerp(_ p: Double, _ q: Double) -> Double { (level - p) / (q - p) }
            let edges = [CGPoint(x: x + cell * lerp(v0, v1), y: y), CGPoint(x: x + cell, y: y + cell * lerp(v1, v2)),
                         CGPoint(x: x + cell * lerp(v3, v2), y: y + cell), CGPoint(x: x, y: y + cell * lerp(v0, v3))]
            for (a, b) in joins { path.move(to: edges[a]); path.addLine(to: edges[b]) }
        } }
        return path
    }

    /// Seeded 2D gradient noise (Perlin), about -0.7...0.7.
    struct Noise {
        private var perm = [Int](repeating: 0, count: 512)
        private var grads: [(Double, Double)] = []

        init(seed: UInt32) {
            var s = seed
            func next() -> Double { s = s &* 1_664_525 &+ 1_013_904_223; return Double(s) / 4_294_967_296 }
            var p = Array(0..<256)
            for i in stride(from: 255, to: 0, by: -1) { p.swapAt(i, Int(next() * Double(i + 1))) }
            for i in 0..<512 { perm[i] = p[i & 255] }
            grads = (0..<256).map { _ in let a = next() * .pi * 2; return (cos(a), sin(a)) }
        }

        func at(_ x: Double, _ y: Double) -> Double {
            let xi = Int(floor(x)), yi = Int(floor(y)), xf = x - floor(x), yf = y - floor(y)
            func dot(_ ix: Int, _ iy: Int, _ dx: Double, _ dy: Double) -> Double {
                let g = grads[perm[(perm[ix & 255] + (iy & 255)) & 511] & 255]
                return g.0 * dx + g.1 * dy
            }
            func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
            let u = fade(xf), v = fade(yf)
            let a = dot(xi, yi, xf, yf), b = dot(xi + 1, yi, xf - 1, yf)
            let c = dot(xi, yi + 1, xf, yf - 1), d = dot(xi + 1, yi + 1, xf - 1, yf - 1)
            let top = a + (b - a) * u, bottom = c + (d - c) * u
            return top + (bottom - top) * v
        }
    }
}
