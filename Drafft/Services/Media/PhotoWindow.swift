import CoreGraphics
import Nuke

/// The deck's photos fetched ahead, as a window that moves with every swipe (the way a list prefetches
/// the rows about to scroll in). The cards on screen load their own photo, the one in play first
/// (`SwipeCard`'s priority); the window covers what comes after them:
///
/// - on a good connection, the portraits of the next 6 cards, to disk, at the copy their card needs, then
///   the other photos of the card in play (its profile, if opened);
/// - on a limited one (`NetworkQuality`), a small copy of the portraits on screen and of the next 8 instead
///   (`Images.preview`, about 20 kB each): a full copy can't keep up with fast swipes on a slow line, a
///   small one can, so no card shows only its blurred preview. The cards behind the one in play get their
///   full copy last (`SwipeCard`'s priority).
///
/// Whatever leaves the window is cancelled: a fast run of swipes never leaves downloads running for cards
/// already gone, which would take the line from the card in play.
@MainActor
final class PhotoWindow {
    static let deck = PhotoWindow()

    /// Two at a time each, under the six (two when limited) the pipeline allows: the cards on screen
    /// always have room. Small copies are decoded ahead too (under a megabyte each): shown on arrival.
    private let portraits = ImagePrefetcher(destination: .diskCache, maxConcurrentRequestCount: 2)
    private let previews = ImagePrefetcher(destination: .memoryCache, maxConcurrentRequestCount: 2)
    private let extras = ImagePrefetcher(destination: .diskCache, maxConcurrentRequestCount: 1)
    private var current: [ObjectIdentifier: [ImageRequest]] = [:]

    /// The last aim, taken again when the connection changes (`NetworkQuality`): the full copies a
    /// limited line can't afford stop at once, not at the next swipe.
    private var last: (deck: [Profile], onScreen: Int, points: CGSize, scale: CGFloat)?

    private init() {
        NetworkQuality.shared.onChange { _ in
            Task { @MainActor in
                guard let last = PhotoWindow.deck.last else { return }
                PhotoWindow.deck.aim(deck: last.deck, onScreen: last.onScreen, points: last.points, scale: last.scale)
            }
        }
        portraits.priority = .low
        // Ahead of the card in play's full copy too (`DiscoverView.photoPriority`): small enough to keep up.
        previews.priority = .veryHigh
        extras.priority = .veryLow
    }

    /// Aims the window after the `onScreen` cards of `deck` (portraits, then each profile's other photos),
    /// drawn in a frame of `points`.
    func aim(deck: [Profile], onScreen: Int, points: CGSize, scale: CGFloat) {
        guard points.width > 0, points.height > 0 else { return }
        last = (deck, onScreen, points, scale)
        let limited = NetworkQuality.shared.isLimited
        let ahead = limited ? [] : deck.dropFirst(onScreen).prefix(6).map(\.portrait)
        set(portraits, ahead.compactMap { Images.download($0, points: points, scale: scale, priority: .low) })
        set(previews, limited
            ? deck.prefix(onScreen + 8).map(\.portrait).compactMap { Images.preview($0, points: points, scale: scale) }
            : [])
        set(extras, limited ? [] : (deck.first?.photos ?? [])
            .compactMap { Images.download($0, points: points, scale: scale, priority: .veryLow) })
    }

    /// Everything stops (the deck is gone, another screen).
    func clear() {
        last = nil
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
