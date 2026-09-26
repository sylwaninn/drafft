import UIKit

/// Photos made ahead of time of athletes mid-effort (HYROX, running, climbing…), diverse in
/// origin, skin and build. Never real users. Two uses:
/// - the pile you stand out from in the boost, super like and likes sheets: people like you
///   (`DiscoverFilters.audience(of: me)`);
/// - Discover's empty stack: the people you're looking for (`filters.audience`).
enum PackPhotos {
    /// Where the person looks or turns in the frame.
    enum Facing { case left, front, right }
    /// What the body is doing: a pile reads natural when poses differ.
    enum Pose { case resting, moving, closeUp }
    /// Where and how they train: a pile never shows the same kind of sport twice when it can.
    enum Setting { case gym, climbing, mountain, street, cycling }

    struct Shot {
        let name: String
        let isWoman: Bool
        /// An abstract appearance group, only compared for equality: two shots in the same group
        /// look alike, so a pile avoids pairing them.
        let look: Int
        let facing: Facing
        let pose: Pose
        let setting: Setting
        /// Coarse lightness of skin, only used so two people of the same gender in one pile never
        /// read alike: one lighter, one darker.
        var light = false
        /// Only used when the pool has nothing better: a look-alike of a preferred shot.
        var spare = false
    }

    static let shots: [Shot] = [
        Shot(name: "pack_man_1", isWoman: false, look: 1, facing: .front, pose: .resting, setting: .gym),
        Shot(name: "pack_man_2", isWoman: false, look: 2, facing: .left, pose: .moving, setting: .gym, light: true),
        Shot(name: "pack_man_3", isWoman: false, look: 6, facing: .left, pose: .moving, setting: .mountain),
        Shot(name: "pack_man_4", isWoman: false, look: 1, facing: .front, pose: .moving, setting: .cycling),
        Shot(name: "pack_woman_1", isWoman: true, look: 3, facing: .left, pose: .moving, setting: .climbing, light: true),
        Shot(name: "pack_woman_2", isWoman: true, look: 3, facing: .front, pose: .resting, setting: .gym, spare: true),
        Shot(name: "pack_woman_3", isWoman: true, look: 1, facing: .front, pose: .closeUp, setting: .street),
        Shot(name: "pack_woman_4", isWoman: true, look: 4, facing: .right, pose: .moving, setting: .gym)
    ]

    /// A fresh pick for an audience, never two of the same kind of sport (fewer than `count` if the
    /// pool can't), otherwise as varied as it allows (different looks first, then
    /// different facings and poses), in an order where neighbours differ. Non-binary and everyone
    /// mix women and men.
    static func pick(for audience: DiscoverFilters.Audience, count: Int = 3) -> [String] {
        let pool = shots.filter { UIImage(named: $0.name) != nil }.filter { s in
            switch audience {
            case .women: s.isWoman
            case .men: !s.isWoman
            case .nonBinary, .everyone: true
            }
        }
        let mixes = audience == .nonBinary || audience == .everyone
        var picked: [Shot] = []
        var rest = pool.shuffled()
        func value(_ i: Int) -> Int { score(rest[i], after: picked, mixes: mixes) }
        // Never the same kind of sport twice: a smaller pile rather than a repeat.
        while picked.count < count,
              let best = rest.indices.filter({ i in !picked.contains { $0.setting == rest[i].setting } })
                  .max(by: { value($0) < value($1) }) {
            picked.append(rest.remove(at: best))
        }
        return picked.map(\.name)
    }

    /// Higher is better: (mixed piles) the other gender first, then for a second person of the same
    /// gender a different skin lightness, then a new look, a new facing, a
    /// new pose, and a preferred shot over its spare.
    private static func score(_ s: Shot, after picked: [Shot], mixes: Bool) -> Int {
        var v = s.spare ? 0 : 1
        if mixes, let last = picked.last, last.isWoman != s.isWoman { v += 32 }
        // Same gender twice: one lighter, one darker.
        if let twin = picked.first(where: { $0.isWoman == s.isWoman }), twin.light != s.light { v += 24 }
        if !picked.contains(where: { $0.look == s.look }) { v += 16 }
        if picked.last?.facing != s.facing { v += 8 }
        if !picked.contains(where: { $0.pose == s.pose }) { v += 4 }
        return v
    }
}
