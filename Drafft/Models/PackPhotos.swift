import UIKit

/// The people behind your card in the boost, super like and likes sheets: photos made ahead of
/// time of athletes mid-effort (HYROX, running, cycling, trail…), diverse in origin, skin and build.
/// It's the pile you stand out from, so they share your gender: women for a woman, men for a man,
/// both mixed for a non-binary person. Never real users.
enum PackPhotos {
    static let women = (1...6).map { "pack_woman_\($0)" }
    static let men = (1...6).map { "pack_man_\($0)" }
    // Missing numbers are skipped: the pool grows as photos are added.

    /// A fresh pick each time the sheet opens.
    static func pick(for audience: DiscoverFilters.Audience, count: Int = 3) -> [String] {
        let w = available(women), m = available(men)
        switch audience {
        case .women: return Array(w.prefix(count))
        case .men: return Array(m.prefix(count))
        case .nonBinary, .everyone:
            let pair = Bool.random() ? [w, m] : [m, w]
            return (0..<count).compactMap { i in pair[i % 2].indices.contains(i / 2) ? pair[i % 2][i / 2] : nil }
        }
    }

    private static func available(_ names: [String]) -> [String] {
        names.filter { UIImage(named: $0) != nil }.shuffled()
    }
}
