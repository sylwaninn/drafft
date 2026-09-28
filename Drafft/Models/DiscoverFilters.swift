import Foundation

/// Who to show in Discover. Empty sets mean "any". Only the sports and "In common" are filters (the
/// badge, "Clear filters"); distance, age and who you want to meet are the search itself. Kept on
/// this iPhone between launches.
struct DiscoverFilters: Equatable, Codable {
    enum Audience: String, CaseIterable, Identifiable, Codable {
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

    /// Clears the filters (sports, "In common"), keeping distance, age and who you want to meet.
    func cleared() -> DiscoverFilters {
        var f = self
        f.sports = []
        f.sharedSportsOnly = false
        return f
    }

    /// Filters in use, for the badge: the sports and "In common" only.
    var activeCount: Int {
        [!sports.isEmpty, sharedSportsOnly].filter { $0 }.count
    }

    private static let storageKey = "discoverFilters"

    /// The last search on this iPhone, or the defaults.
    static var saved: DiscoverFilters {
        UserDefaults.standard.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(DiscoverFilters.self, from: $0) } ?? DiscoverFilters()
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.storageKey)
    }

    /// The person's own gender; without one (an unfinished sign-up), their pronouns.
    static func audience(of p: Profile) -> Audience {
        if let gender = p.gender { return gender }
        return switch p.pronouns {
        case "she/her": .women
        case "he/him": .men
        default: .nonBinary
        }
    }
}
