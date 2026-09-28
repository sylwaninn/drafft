import SwiftUI

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

/// The contour lines of `ContourLines`: a frozen terrain per block type, traced with marching squares.
/// The terrain is sampled once per block type (rows added as blocks grow), and each height's lines are
/// traced once: a block that changes size frame by frame (an animation) only runs marching squares, and
/// every cache is bounded. The output is exactly the original tracer's (tested in ContourTraceTests).
enum ContourTrace {
    struct Line { let path: Path; let index: Bool }

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

    /// Terrain samples on the fixed reference grid, in rows added on demand, with running minimum and
    /// maximum per row so any height's normalisation is read, not recomputed.
    private final class Terrain {
        let cols: Int
        let levels: Int
        private let hills: [Hill]
        private let waves: [(a: Double, f: Double, p: Double)]
        private(set) var grid: [Double] = []
        private var lows: [Double] = []
        private var highs: [Double] = []

        init(seed: String, cols: Int) {
            let style = styles[seed] ?? Style(summit: .topTrailing, hills: 4, levels: 16)
            var rng = SeededRandom("\(seed)-\(terrainVersions[seed] ?? "relief-5")")
            let width = Double(refSize.width), height = Double(refSize.height)

            // Main summit near the style's anchor, then secondary hills spread around it.
            var hills = [Hill(x: Double(style.summit.x) * width, y: Double(style.summit.y) * height,
                              rx: 190 + Double(rng.next()) * 80, ry: 140 + Double(rng.next()) * 60,
                              h: 1.0, angle: Double(rng.next()) * .pi)]
            for _ in 0..<style.hills {
                hills.append(Hill(x: Double(rng.next()) * width * 1.2 - width * 0.1,
                                  y: Double(rng.next()) * height * 1.2 - height * 0.1,
                                  rx: 80 + Double(rng.next()) * 110, ry: 60 + Double(rng.next()) * 80,
                                  h: 0.15 + Double(rng.next()) * 0.3, angle: Double(rng.next()) * .pi))
            }
            // Low-frequency undulation so slopes aren't perfectly smooth.
            waves = (0..<3).map { _ in (a: Double(rng.next()) * .pi * 2, f: 0.012 + Double(rng.next()) * 0.02,
                                        p: Double(rng.next()) * .pi * 2) }
            self.hills = hills
            self.cols = cols
            self.levels = style.levels
        }

        private func height(_ x: Double, _ y: Double) -> Double {
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

        /// Samples rows until there are `rows`; the lowest and highest height over the first `rows` rows.
        func range(rows: Int) -> (lo: Double, hi: Double) {
            while lows.count < rows {
                let r = lows.count
                var lo = r == 0 ? Double.greatestFiniteMagnitude : lows[r - 1]
                var hi = r == 0 ? -Double.greatestFiniteMagnitude : highs[r - 1]
                for c in 0..<cols {
                    let z = height(Double(c) * cell, Double(r) * cell)
                    grid.append(z)
                    lo = min(lo, z); hi = max(hi, z)
                }
                lows.append(lo); highs.append(hi)
            }
            return (lows[rows - 1], highs[rows - 1])
        }
    }

    /// Grid step, in reference units.
    private static let cell = 5.0
    private static let lock = NSLock()
    nonisolated(unsafe) private static var terrains = BoundedCache<String, Terrain>(limit: 16)
    nonisolated(unsafe) private static var traced = BoundedCache<String, [Line]>(limit: 48)

    /// Entries held right now (tests).
    static var cachedCounts: (terrains: Int, lines: Int) {
        lock.lock(); defer { lock.unlock() }
        return (terrains.count, traced.count)
    }

    static func lines(seed: String, size: CGSize) -> [Line] {
        let key = "\(seed)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        lock.lock(); defer { lock.unlock() }
        if let hit = traced[key] { return hit }
        let out = traceLocked(seed: seed, size: size)
        traced[key] = out
        return out
    }

    /// Traces without the lines cache (the terrain's is used); `lines` is the entry point.
    static func trace(seed: String, size: CGSize) -> [Line] {
        lock.lock(); defer { lock.unlock() }
        return traceLocked(seed: seed, size: size)
    }

    private static func traceLocked(seed: String, size: CGSize) -> [Line] {
        // The terrain's grid covers the visible block (in reference units).
        let scale = Double(refSize.width) / Double(max(size.width, 1))
        let cols = Int(Double(size.width) * scale / cell) + 2
        let rows = Int(Double(size.height) * scale / cell) + 2
        let terrainKey = "\(seed)|\(cols)"
        let terrain = terrains[terrainKey] ?? Terrain(seed: seed, cols: cols)
        terrains[terrainKey] = terrain
        let (lo, hi) = terrain.range(rows: rows)
        let grid = terrain.grid
        let toView = CGFloat(1 / scale)

        // Marching squares, one path per level; every fifth level is an index contour.
        return (1...terrain.levels).map { li in
            let level = lo + (hi - lo) * Double(li) / Double(terrain.levels + 1)
            return Line(path: march(grid, cols: cols, rows: rows, level: level, toView: toView), index: li.isMultiple(of: 5))
        }
    }

    // One case per marching-squares configuration: splitting it would hide the table.
    // swiftlint:disable:next cyclomatic_complexity
    private static func march(_ grid: [Double], cols: Int, rows: Int, level: Double, toView: CGFloat) -> Path {
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
        return path
    }
}

/// A dictionary with a size limit: the least recently used entry goes first. Not thread-safe (callers lock).
struct BoundedCache<Key: Hashable, Value> {
    let limit: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    init(limit: Int) { self.limit = max(1, limit) }

    var count: Int { values.count }

    subscript(key: Key) -> Value? {
        mutating get {
            guard let value = values[key] else { return nil }
            touch(key)
            return value
        }
        set {
            guard let newValue else {
                values[key] = nil
                order.removeAll { $0 == key }
                return
            }
            if values.updateValue(newValue, forKey: key) == nil, values.count > limit {
                values[order.removeFirst()] = nil
            }
            touch(key)
        }
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
