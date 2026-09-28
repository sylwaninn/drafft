import Foundation

/// Deterministic pseudo-random waveform, so a voice intro without levels still looks distinct and stable.
enum Waveform {
    static func seeded(_ seed: String, count: Int) -> [Float] {
        var h: UInt64 = 1469598103934665603
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return (0..<count).map { i in
            h = h &* 6364136223846793005 &+ 1442695040888963407
            let r = Float((h >> 33) % 1000) / 1000
            let envelope = sin(Float(i) / Float(count) * .pi) * 0.55 + 0.45
            return max(0.12, min(1, r * envelope + 0.1))
        }
    }
}
