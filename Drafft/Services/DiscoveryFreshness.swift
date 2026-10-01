import Foundation

/// When discovery is read again without anyone asking (back at the front, Discover shown again, the
/// account's channel rejoined): only the parts older than that moment allows, so a quick trip to another
/// app or tab reads nothing and a long one reads everything, quietly. Every read of a part counts,
/// whoever asked for it (a live event, the Likes tab, a swipe): the same list is never read twice in a
/// row for nothing.
///
/// It also keeps reads of one part in order: an answer that lands after a newer one was applied is
/// dropped (`finish`), so a slow, older read never puts back what a newer one removed.
struct DiscoveryFreshness {
    enum Part: CaseIterable { case deck, likes, matches, likesLeft }

    /// What asks for the read.
    enum Moment {
        /// In: signed in, sign-up finished, a hold lifted, a pause ended. Everything, now.
        case entered
        /// The account's channel (re)joined: events were maybe missed while it was down. Everything, now.
        case reconnected
        /// Back at the front.
        case foreground
        /// The Discover tab shown again.
        case tabShown

        /// How old (seconds) a part may be at that moment before it's read again.
        var maxAge: TimeInterval {
            switch self {
            case .entered, .reconnected: 0
            case .foreground: 30
            case .tabShown: 60
            }
        }
    }

    /// A read still running after this long is taken as lost (a request cut short by the background):
    /// it no longer counts as fresh, and the next moment reads again.
    static let lostAfter: TimeInterval = 20

    /// One read of a part, numbered in the order they started.
    struct Read: Equatable {
        let part: Part
        let number: Int
        /// Seconds on a monotonic clock: what the read shows is the server as of then.
        let startedAt: TimeInterval
    }

    private var started = 0
    /// When the last applied read of each part started.
    private var readAt: [Part: TimeInterval] = [:]
    /// The newest read of each part still on its way.
    private var running: [Part: Read] = [:]
    /// The number of the last read applied, by part.
    private var applied: [Part: Int] = [:]

    /// Whether `part` should be read again at `moment`. A read on its way counts from when it started,
    /// unless it looks lost.
    func isDue(_ part: Part, for moment: Moment, now: TimeInterval) -> Bool {
        var latest = readAt[part]
        if let run = running[part], now - run.startedAt < Self.lostAfter {
            latest = max(latest ?? run.startedAt, run.startedAt)
        }
        guard let latest else { return true }
        return now - latest >= moment.maxAge
    }

    /// A read of `part` starts now.
    mutating func start(_ part: Part, now: TimeInterval) -> Read {
        started += 1
        let read = Read(part: part, number: started, startedAt: now)
        running[part] = read
        return read
    }

    /// A read came back, with what the server sent (`ok`) or not. Whether to apply it: never a failed
    /// read, nor one older than a read already applied.
    mutating func finish(_ read: Read, ok: Bool) -> Bool {
        if running[read.part] == read { running[read.part] = nil }
        guard ok, read.number > applied[read.part, default: 0] else { return false }
        applied[read.part] = read.number
        readAt[read.part] = read.startedAt
        return true
    }
}
