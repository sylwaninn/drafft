import CoreGraphics
import Nuke

/// The deck's photos fetched ahead, as a window that moves with every swipe (the way a list prefetches
/// the rows about to scroll in). The cards on screen load their own photo, the one in play first
/// (`SwipeCard`'s priority); the window covers what comes after them:
///
/// - the portraits of the next cards, to disk, at the copy their card needs: 6 ahead, 4 on a limited
///   connection (`NetworkQuality`);
/// - on a limited connection, a small copy of each of those portraits first (`Images.preview`), so a card
///   never shows only its blurred preview;
/// - the other photos of the card in play (its profile, if opened), last, and only on a good connection.
///
/// Whatever leaves the window is cancelled: a fast run of swipes never leaves downloads running for cards
/// already gone, which would take the line from the card in play.
@MainActor
final class PhotoWindow {
    static let deck = PhotoWindow()

    /// Two at a time each, under the six (three when limited) the pipeline allows: the cards on screen
    /// always have room.
    private let portraits = ImagePrefetcher(destination: .diskCache, maxConcurrentRequestCount: 2)
    private let previews = ImagePrefetcher(destination: .diskCache, maxConcurrentRequestCount: 2)
    private let extras = ImagePrefetcher(destination: .diskCache, maxConcurrentRequestCount: 1)
    private var current: [ObjectIdentifier: [ImageRequest]] = [:]

    private init() {
        portraits.priority = .low
        previews.priority = .normal
        extras.priority = .veryLow
    }

    /// Aims the window after the `onScreen` cards of `deck` (portraits, then each profile's other photos),
    /// drawn in a frame of `points`.
    func aim(deck: [Profile], onScreen: Int, points: CGSize, scale: CGFloat) {
        guard points.width > 0, points.height > 0 else { return }
        let limited = NetworkQuality.shared.isLimited
        let ahead = deck.dropFirst(onScreen).prefix(limited ? 4 : 6).map(\.portrait)
        set(portraits, ahead.compactMap { Images.request($0, points: points, scale: scale, priority: .low) })
        set(previews, limited
            ? deck.prefix(onScreen + 4).map(\.portrait).compactMap { Images.preview($0, points: points, scale: scale) }
            : [])
        set(extras, limited ? [] : (deck.first?.photos ?? [])
            .compactMap { Images.request($0, points: points, scale: scale, priority: .veryLow) })
    }

    /// Everything stops (the deck is gone, another screen).
    func clear() {
        for prefetcher in [portraits, previews, extras] { set(prefetcher, []) }
    }

    private func set(_ prefetcher: ImagePrefetcher, _ requests: [ImageRequest]) {
        let id = ObjectIdentifier(prefetcher)
        let keep = Set(requests.map(Self.key))
        let gone = (current[id] ?? []).filter { !keep.contains(Self.key($0)) }
        if !gone.isEmpty { prefetcher.stopPrefetching(with: gone) }
        if !requests.isEmpty { prefetcher.startPrefetching(with: requests) }
        current[id] = requests
    }

    private static func key(_ request: ImageRequest) -> String {
        request.imageID ?? request.url?.absoluteString ?? ""
    }
}
