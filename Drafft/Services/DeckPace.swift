import Foundation

/// When to ask for the next batch of cards: early enough that it arrives, with its first photos, before
/// the person reaches the end at the pace they swipe. Measured rather than guessed: how long the last
/// reads took and how fast the last swipes came, as averages that follow the recent ones. A pause (reading
/// a profile, putting the phone down) doesn't count as a pace.
struct DeckPace {
    /// Cards per read.
    static let batch = 20
    /// Never fewer cards left than this when the next read starts.
    static let floor = 10
    /// The cards whose photos are fetched ahead of the ones on screen (`PhotoWindow`): a new batch has to
    /// be there before the window runs out.
    static let photoLead = 6

    private(set) var readSeconds = 1.5
    private(set) var swipeSeconds = 0.8
    private var lastSwipe: TimeInterval?

    /// A deck read that took `seconds`.
    mutating func read(took seconds: TimeInterval) {
        readSeconds = readSeconds * 0.5 + max(0, seconds) * 0.5
    }

    /// A swipe at `now` (seconds on a monotonic clock).
    mutating func swiped(at now: TimeInterval) {
        if let lastSwipe, now - lastSwipe < 5 {
            swipeSeconds = swipeSeconds * 0.7 + max(0.15, now - lastSwipe) * 0.3
        }
        lastSwipe = now
    }

    /// Cards left that ask for the next batch: the swipes a read lasts, plus the photo window; at least
    /// `floor`, and short of a whole batch (a read must leave something new to swipe).
    var lowWater: Int {
        let duringRead = Int((readSeconds / swipeSeconds).rounded(.up))
        return min(Self.batch - 2, max(Self.floor, duringRead + Self.photoLead))
    }
}
