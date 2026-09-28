import XCTest
import SwiftUI

final class ContourTraceTests: XCTestCase {
    private let seeds = [BackdropSeed.voice, BackdropSeed.icebreaker, BackdropSeed.goal, BackdropSeed.sport,
                         BackdropSeed.session, BackdropSeed.me, BackdropSeed.deckEmpty, BackdropSeed.nextSession, "other"]

    /// The terrains are frozen: the cached tracer draws exactly what the original one did, whatever
    /// order the sizes come in (rows are added to a terrain as blocks grow).
    func testMatchesTheOriginalTracer() {
        let sizes = [CGSize(width: 361, height: 180), CGSize(width: 361, height: 96), CGSize(width: 361, height: 412.5),
                     CGSize(width: 329, height: 240), CGSize(width: 402, height: 131)]
        for seed in seeds {
            for size in sizes {
                let new = ContourTrace.lines(seed: seed, size: size)
                let old = ReferenceContour.trace(seed: seed, size: size)
                XCTAssertEqual(new.count, old.count, "\(seed) \(size)")
                for (a, b) in zip(new, old) {
                    XCTAssertEqual(a.index, b.index)
                    XCTAssertEqual(a.path, b.path, "\(seed) \(size)")
                }
            }
        }
    }

    func testCachesStayBounded() {
        for h in 0..<300 { _ = ContourTrace.lines(seed: BackdropSeed.voice, size: CGSize(width: 361, height: 100 + Double(h))) }
        let counts = ContourTrace.cachedCounts
        XCTAssertLessThanOrEqual(counts.lines, 48)
        XCTAssertLessThanOrEqual(counts.terrains, 16)
    }

    func testBoundedCacheDropsLeastRecentlyUsed() {
        var cache = BoundedCache<Int, String>(limit: 2)
        cache[1] = "a"; cache[2] = "b"
        _ = cache[1]
        cache[3] = "c"
        XCTAssertEqual(cache[1], "a")
        XCTAssertNil(cache[2])
        XCTAssertEqual(cache[3], "c")
        XCTAssertEqual(cache.count, 2)
    }

    /// A block growing by 1 pt per frame over 300 frames (an expanding card), original tracer.
    func testOriginalTracerDuringAResize() {
        measure {
            for h in 0..<300 {
                _ = ReferenceContour.trace(seed: BackdropSeed.icebreaker, size: CGSize(width: 361, height: 150 + Double(h)))
            }
        }
    }

    /// The same resize with the cached tracer, bypassing the lines cache: the terrain is sampled once,
    /// each new height only runs marching squares.
    func testCachedTracerDuringAResize() {
        measure {
            for h in 0..<300 {
                _ = ContourTrace.trace(seed: BackdropSeed.icebreaker, size: CGSize(width: 361, height: 150 + Double(h)))
            }
        }
    }
}

// swiftlint:disable cyclomatic_complexity identifier_name legacy_multiple
/// The original tracer, copied verbatim before the cache: the reference the new one must match.
private enum ReferenceContour {
    typealias Line = ContourTrace.Line
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
    static func trace(seed: String, size: CGSize) -> [Line] {
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
// swiftlint:enable cyclomatic_complexity identifier_name legacy_multiple
