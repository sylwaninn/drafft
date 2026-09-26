import Foundation

/// Who to show in Discover. Empty sets mean "any".
struct DiscoverFilters: Equatable {
    enum Audience: String, CaseIterable, Identifiable {
        case women = "Women", men = "Men", nonBinary = "Non-binary people", everyone = "Everyone"
        var id: String { rawValue }
        /// A gender as sign-up asks it ("Woman") or the server stores it ("woman").
        init?(answer: String) {
            switch answer.lowercased() {
            case "woman", "women": self = .women
            case "man", "men": self = .men
            case "non-binary", "nonbinary", "non-binary people": self = .nonBinary
            default: return nil
            }
        }
        /// Shown in the app's language; `rawValue` stays the stable identity.
        var title: String {
            switch self {
            case .women: L("Women")
            case .men: L("Men")
            case .nonBinary: L("Non-binary people")
            case .everyone: L("Everyone")
            }
        }
    }

    static let ageBounds = 18...60
    static let distanceBounds = 1.0...50.0
    /// The slider's last stop: "50+", meaning no distance limit.
    static let anyDistance = 51.0

    var anyDistance: Bool { maxDistanceKm >= Self.anyDistance }
    /// "Up to 10 km", or "Any distance" at the last stop.
    var distanceLabel: String { anyDistance ? L("Any distance") : L("Up to \(Int(maxDistanceKm)) km") }
    /// Short form for pills: "10 km" or "50+ km".
    var distanceShort: String { anyDistance ? L("50+ km") : L("\(Int(maxDistanceKm)) km") }

    var maxDistanceKm = 10.0
    var ages = 25...40
    var audience: Audience = .everyone
    var sports: Set<Sport> = []
    var sharedSportsOnly = false

    /// Resets distance, age, sports and schedule, keeping who you want to meet.
    func loosened() -> DiscoverFilters {
        var f = DiscoverFilters()
        f.audience = audience
        return f
    }

    /// Number of filters changed from the defaults, for the badge.
    var activeCount: Int {
        let d = DiscoverFilters()
        return [maxDistanceKm != d.maxDistanceKm, ages != d.ages, audience != d.audience,
                !sports.isEmpty, sharedSportsOnly].filter { $0 }.count
    }

    func matches(_ p: Profile, me: Profile) -> Bool {
        guard anyDistance || p.distanceKm <= maxDistanceKm, ages.contains(p.age) else { return false }
        if audience != .everyone && Self.audience(of: p) != audience { return false }
        if !sports.isEmpty && !p.sports.contains(where: { sports.contains($0.sport) }) { return false }
        if sharedSportsOnly && !p.sports.contains(where: { s in me.sports.contains { $0.sport == s.sport } }) {
            return false
        }
        return true
    }

    /// The person's own gender; demo profiles without one fall back on their pronouns.
    static func audience(of p: Profile) -> Audience {
        if let gender = p.gender { return gender }
        return switch p.pronouns {
        case "she/her": .women
        case "he/him": .men
        default: .nonBinary
        }
    }
}
