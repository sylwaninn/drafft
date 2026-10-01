import Foundation

/// How long ago someone liked you, in the one coarse unit the Likes tiles show ("5 min ago", "2 days
/// ago", "1 year ago"). Computed from the server's real `likedAt`, never invented; a like that has no
/// date shows no label at all.
///
/// Boundaries (floor in each unit, so the label never overstates): under a minute is "just now" (a
/// clock slightly ahead of the server's lands there too), then minutes up to 59, hours up to 23, days
/// up to 29, months (30 days each) up to 11, then years (365 days each).
enum LikeAge: Equatable {
    case now
    case minutes(Int)
    case hours(Int)
    case days(Int)
    case months(Int)
    case years(Int)

    init(from date: Date, to now: Date) {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<60: self = .now
        case ..<3_600: self = .minutes(seconds / 60)
        case ..<86_400: self = .hours(seconds / 3_600)
        default:
            let days = seconds / 86_400
            switch days {
            case ..<30: self = .days(days)
            case ..<365: self = .months(min(days / 30, 11))
            default: self = .years(days / 365)
            }
        }
    }

    /// Lowercase in every language; plurals come from the catalog's plural variations.
    var text: String {
        switch self {
        case .now: L("just now")
        case .minutes(let n): L("\(n) min ago")
        case .hours(let n): L("\(n) hr ago")
        case .days(let n): L("\(n) days ago")
        case .months(let n): L("\(n) months ago")
        case .years(let n): L("\(n) years ago")
        }
    }
}

extension LikeAge {
    /// The tile's label, or nil when the like has no date (nothing is shown rather than a guess).
    static func text(of date: Date?, at now: Date) -> String? {
        date.map { LikeAge(from: $0, to: now).text }
    }
}

/// Likes are listed newest first, always: a super like doesn't jump the queue. Equal or missing dates
/// keep a stable order (missing ones last, then by id).
enum LikeOrder {
    static func newestFirst<T>(_ items: [T], date: (T) -> Date?, id: (T) -> String) -> [T] {
        items.sorted { a, b in
            switch (date(a), date(b)) {
            case let (x?, y?) where x != y: x > y
            case (.some, .none): true
            case (.none, .some): false
            default: id(a) < id(b)
            }
        }
    }
}
