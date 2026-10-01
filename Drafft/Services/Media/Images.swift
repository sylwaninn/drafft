import Foundation
import Nuke
import UIKit

/// Every photo that isn't bundled with the app (on the server, or picked on this phone) goes
/// through one Nuke pipeline:
///
/// - decoded in the background, straight at the size it's drawn (ImageIO thumbnail), never the
///   full bitmap on the main thread;
/// - one download per photo, however many views ask for it at once;
/// - a capped memory cache, emptied on a memory warning, and a capped disk cache of the
///   downloaded bytes (keys never change, so a photo is downloaded once);
/// - both caches keyed by the object (`MediaURL.canonical`), never by its signed link: a photo stays
///   cached when its link is renewed, and a link about to expire is renewed before it's downloaded;
/// - the media Worker sends a copy at the display width (`&w=`) instead of the 2048 px original
///   whenever a smaller one is enough (thumbnails, grids, avatars).
enum Images {
    /// Decoded photos kept in memory (the system can still evict them earlier).
    static let memoryLimit = 120 << 20
    /// Downloaded bytes kept on disk.
    static let diskLimit = 300 << 20
    /// Pixel sizes shared by nearby displays: a size change (rotation, animation) reuses a copy
    /// instead of decoding again, and two avatars a few points apart share one.
    private static let buckets = [128, 256, 512, 768, 1_080, 1_440]
    private static let largest = 2_048

    /// Once, at launch, before the first photo is drawn.
    static func configure() {
        let memory = ImageCache(costLimit: memoryLimit)
        ImagePipeline.shared = ImagePipeline { config in
            let session = URLSessionConfiguration.default
            session.urlCache = nil // the disk cache below keeps the bytes
            session.timeoutIntervalForRequest = 30
            config.dataLoader = SignedLinkLoader(DataLoader(configuration: session))
            let disk = try? DataCache(name: "so.drafft.images")
            disk?.sizeLimit = diskLimit
            config.dataCache = disk
            config.imageCache = memory
        }
        // Nuke trims when the app goes to the background; a warning in the foreground empties it too.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { _ in memory.removeAll() }
    }

    /// The request for a photo drawn in a frame of `points` (nil for a photo that isn't ours to
    /// load: a bundled asset name). `/…` is a file on this phone, `http…` a photo on the server.
    /// `blur`: a radius as a share of the photo's shorter side, applied once when it's decoded.
    static func request(_ name: String, points: CGSize, scale: CGFloat = 3, priority: ImageRequest.Priority = .normal,
                        blur: CGFloat = 0) -> ImageRequest? {
        let pixels = bucket(max(points.width, points.height) * scale)
        let url: URL?
        var options: ImageRequest.Options = []
        if name.hasPrefix("/") {
            url = URL(fileURLWithPath: name)
            options.insert(.disableDiskCache) // already on disk
        } else if name.hasPrefix("http") {
            url = sized(name, width: pixels)
        } else {
            return nil
        }
        guard let url else { return nil }
        var request = ImageRequest(url: url, priority: priority, options: options)
        if !url.isFileURL { request.imageID = MediaURL.canonical(url).absoluteString }
        // Square box, aspect fill: the copy covers the frame whatever its proportions.
        request.thumbnail = .init(size: CGSize(width: pixels, height: pixels), unit: .pixels, contentMode: .aspectFill)
        if blur > 0 { request.processors = [.gaussianBlur(radius: max(1, Int(blur * CGFloat(pixels))))] }
        return request
    }

    /// Starts downloading photos that are about to show (the next cards of the deck), to disk:
    /// they're decoded at their display size once they're drawn.
    /// `points` is the frame they'll be drawn in, so the server-sized copy is the one fetched.
    static func prefetch(_ names: [String], points: CGSize) {
        let requests = names.filter { $0.hasPrefix("http") }.compactMap { request($0, points: points, priority: .low) }
        guard !requests.isEmpty else { return }
        prefetcher.startPrefetching(with: requests)
    }

    private static let prefetcher = ImagePrefetcher(destination: .diskCache)

    private static func bucket(_ pixels: CGFloat) -> Int {
        buckets.first { CGFloat($0) >= pixels } ?? largest
    }

    // MARK: Sizes served by the media Worker

    /// The widths the media Worker resizes to (cloudflare/media-worker in drafft-backend); any other
    /// value gets the original.
    private static let serverWidths = [160, 320, 640, 1_080]

    /// A signed photo link on the media domain with `&w=` set to the smallest width the Worker serves that
    /// covers `width` pixels; above the largest, the original (2048 px at most). `w` isn't part of the
    /// signature, and the caches keep one copy per width (`MediaURL.canonical`). Other URLs are left as
    /// they are.
    static func sized(_ name: String, width: Int) -> URL? {
        guard let url = URL(string: name) else { return nil }
        guard let base = MediaURL.saved, url.host == base.host, url.scheme == base.scheme,
              MediaURL.key(of: url) != nil,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (parts.queryItems ?? []).filter { $0.name != "w" }
        if let served = serverWidths.first(where: { $0 >= width }) {
            items.append(URLQueryItem(name: "w", value: String(served)))
        }
        parts.queryItems = items.isEmpty ? nil : items
        return parts.url ?? url
    }
}

/// Downloads through Nuke with the media link renewed first when it's about to expire
/// (`MediaURL.fresh`); the cache key stays the object's, whatever the link used.
private final class SignedLinkLoader: DataLoading, @unchecked Sendable {
    private let inner: DataLoader

    init(_ inner: DataLoader) { self.inner = inner }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        guard let url = request.url, !url.isFileURL, MediaURL.expiry(of: url) != nil else {
            return inner.loadData(with: request, didReceiveData: didReceiveData, completion: completion)
        }
        let task = RenewedLoad()
        let inner = inner
        task.start = Task {
            var renewed = request
            renewed.url = await MediaURL.fresh(url)
            guard !Task.isCancelled else { return completion(CancellationError()) }
            task.set(inner.loadData(with: renewed, didReceiveData: didReceiveData, completion: completion))
        }
        return task
    }
}

/// A load that starts once its link is renewed: cancelling it cancels whichever step is running.
private final class RenewedLoad: Cancellable, @unchecked Sendable {
    private let lock = NSLock()
    private var load: (any Cancellable)?
    private var cancelled = false
    var start: Task<Void, Never>?

    func set(_ load: any Cancellable) {
        lock.lock()
        let cancel = cancelled
        if !cancel { self.load = load }
        lock.unlock()
        if cancel { load.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let load = self.load
        lock.unlock()
        start?.cancel()
        load?.cancel()
    }
}
