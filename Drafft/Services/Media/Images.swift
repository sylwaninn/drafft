import Foundation
import Nuke
import UIKit

/// Every photo that isn't bundled with the app (on the server, or picked on this phone) goes
/// through one Nuke pipeline:
///
/// - the copy downloaded is the smallest the frame needs (`Renditions`, from the photo's proportions),
///   or a larger one already on this phone; the media Worker makes each copy once and keeps it;
/// - decoded in the background, straight at the frame's size in pixels and cropped to it (ImageIO
///   thumbnail), never the full bitmap on the main thread: memory holds what the screen shows;
/// - one download per photo, however many views ask for it at once;
/// - a memory cache sized to the phone, emptied on a memory warning, and a capped disk cache of the
///   downloaded bytes (keys never change, so a copy is downloaded once);
/// - both caches keyed by the object and width (`MediaURL.canonical`), never by its signed link: a photo
///   stays cached when its link is renewed, and a link about to expire is renewed before it's downloaded;
/// - on a slow connection (`NetworkQuality`), fewer downloads at once, so the one on screen finishes first.
enum Images {
    /// Decoded photos kept in memory (the system can still evict them earlier): a twentieth of the
    /// phone's memory, between 96 and 256 MB. A deck card is about 7.5 MB (its frame at 3x).
    static let memoryLimit = min(256 << 20, max(96 << 20, Int(ProcessInfo.processInfo.physicalMemory / 20)))
    /// Downloaded bytes kept on disk.
    static let diskLimit = 300 << 20
    #if DECK_PHOTO_METRICS
    /// This launch started from an empty photo cache (`DeckPhotoMetrics`).
    nonisolated(unsafe) static var cachesEmptied = false
    #endif

    /// Once, at launch, before the first photo is drawn.
    static func configure() {
        let memory = ImageCache(costLimit: memoryLimit)
        // Nuke's default (a tenth of the cache) would refuse a full-screen photo.
        memory.entryCostLimit = 0.25
        ImagePipeline.shared = ImagePipeline { config in
            let session = URLSessionConfiguration.default
            session.urlCache = nil // the disk cache below keeps the bytes
            session.timeoutIntervalForRequest = 30
            config.dataLoader = SignedLinkLoader(DataLoader(configuration: session))
            let disk = try? DataCache(name: "so.drafft.images")
            disk?.sizeLimit = diskLimit
            config.dataCache = disk
            config.imageCache = memory
            #if DECK_PHOTO_METRICS
            // A run from an empty cache: launched with `-deckPhotoReset`, or Documents/deck-photo-reset put
            // there for the next launch from the home screen (`devicectl device copy to`).
            let marker = URL.documentsDirectory.appending(path: "deck-photo-reset")
            if ProcessInfo.processInfo.arguments.contains("-deckPhotoReset") || FileManager.default.fileExists(atPath: marker.path) {
                disk?.removeAll()
                try? FileManager.default.removeItem(at: marker)
                cachesEmptied = true
            }
            #endif
        }
        // Nuke trims when the app goes to the background; a warning in the foreground empties it too.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { _ in memory.removeAll() }
        NetworkQuality.shared.onChange { limited in
            // Six downloads share a fast line; on a slow one, two, so the photo on screen isn't split six ways.
            ImagePipeline.shared.configuration.dataLoadingQueue.maxConcurrentOperationCount = limited ? 2 : 6
            #if DECK_PHOTO_METRICS
            Task { @MainActor in DeckPhotoMetrics.network(limited: limited) }
            #endif
        }
    }

    /// The request for a photo drawn in a frame of `points` (nil for a photo that isn't ours to
    /// load: a bundled asset name). `/…` is a file on this phone, `http…` a photo on the server.
    /// `blur`: a radius as a share of the photo's shorter side, applied once when it's decoded.
    /// `variant`: a rendition kept apart in the caches (the server's blurred copy of a like), so it can
    /// never be served for another rendition of the same object, or the other way round.
    /// `detail`: an open profile's photo, which may take a copy wider than `Renditions.everydayWidth`.
    static func request(_ name: String, points: CGSize, scale: CGFloat = 3, priority: ImageRequest.Priority = .normal,
                        blur: CGFloat = 0, variant: String? = nil, detail: Bool = false) -> ImageRequest? {
        let pixels = CGSize(width: points.width * scale, height: points.height * scale)
        let decode = Renditions.decodeSize(for: pixels)
        let url: URL?
        if name.hasPrefix("/") {
            url = URL(fileURLWithPath: name)
        } else if name.hasPrefix("http") {
            url = closest(name, covering: wanted(name, pixels: pixels, detail: detail), variant: variant)
        } else {
            return nil
        }
        guard let url else { return nil }
        return make(url, decode: decode, priority: priority, blur: blur, variant: variant)
    }

    /// A small copy of a server photo for the same frame (`Renditions.previewWidth`), decoded at a third of
    /// its pixels: shown first on a slow connection, under the right copy while it arrives.
    static func preview(_ name: String, points: CGSize, scale: CGFloat = 3) -> ImageRequest? {
        guard name.hasPrefix("http") else { return nil }
        let pixels = CGSize(width: points.width * scale, height: points.height * scale)
        let needed = Renditions.neededWidth(for: pixels, aspect: MediaPreviews.aspect(for: name))
        guard let url = sized(name, width: Renditions.previewWidth(covering: needed)) else { return nil }
        let decode = Renditions.decodeSize(for: CGSize(width: pixels.width / 3, height: pixels.height / 3))
        // Ahead of every full copy but the card in play's: on a slow line, it's what keeps up with the swipes.
        return make(url, decode: decode, priority: .veryHigh, blur: 0, variant: nil)
    }

    /// An open profile's gallery (`ProfileDetailView.gallery`): `galleryHeight` high, the screen's width (an
    /// iPhone app in portrait: every profile opens full width).
    static let galleryHeight: CGFloat = 440
    @MainActor static var galleryFrame: CGSize {
        let width = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }.first
        return CGSize(width: width ?? 393, height: galleryHeight)
    }

    /// Downloads to disk the gallery copy of a profile's first photo (nothing when it's already there): on the
    /// tap that opens it (the sheet's rise gives it a head start), or once its card has been looked at for a
    /// while. Never ahead of every card: most are swiped, never opened. Another call, or the gallery's own
    /// load (same key), joins the download at the highest priority asked; cancelling the caller stops it,
    /// unless another still waits for it.
    @MainActor static func warm(_ name: String, scale: CGFloat, priority: ImageRequest.Priority) async {
        guard let request = download(name, points: galleryFrame, scale: scale, priority: priority, detail: true) else { return }
        // Offline or cancelled: the gallery makes its own request, nothing to report here.
        _ = try? await ImagePipeline.shared.data(for: request)
    }

    /// A copy already on this phone, narrower than the one an open profile's photo will download for the same
    /// frame (`Renditions.standIn`): decoded in the background from disk (the card's decoded copy is another
    /// size), at the sharp copy's decode size and crop, and shown while the right copy arrives. The deck
    /// card's everyday copy, typically, when the gallery wants a wider one.
    static func standIn(_ name: String, points: CGSize, scale: CGFloat = 3) -> ImageRequest? {
        guard name.hasPrefix("http") else { return nil }
        let pixels = CGSize(width: points.width * scale, height: points.height * scale)
        guard let width = Renditions.standIn(covering: wanted(name, pixels: pixels, detail: true),
                                             here: { onDisk(name, width: $0, variant: nil) != nil }),
              let url = sized(name, width: width) else { return nil }
        return make(url, decode: Renditions.decodeSize(for: pixels), priority: .veryHigh, blur: 0, variant: nil)
    }

    /// Starts downloading photos that are about to show, to disk: they're decoded at their display size
    /// once they're drawn. `points` is the frame they'll be drawn in, so the right copy is fetched. The deck
    /// has its own window (`PhotoWindow`); this is for the rest (blurred likes, an open profile's next photos).
    static func prefetch(_ names: [String], points: CGSize, scale: CGFloat = 3, variant: String? = nil, detail: Bool = false) {
        let requests = names.compactMap {
            download($0, points: points, scale: scale, priority: .low, variant: variant, detail: detail)
        }
        guard !requests.isEmpty else { return }
        prefetcher.startPrefetching(with: requests)
    }

    /// The download of the copy `request` would show, for a prefetch to disk: nil when that copy (or a
    /// larger one) is already on this phone. Only the object and width: the decode size and processors
    /// would make Nuke look the bytes up under a key it never stores them under, and download them again.
    static func download(_ name: String, points: CGSize, scale: CGFloat = 3, priority: ImageRequest.Priority,
                         variant: String? = nil, detail: Bool = false) -> ImageRequest? {
        guard name.hasPrefix("http") else { return nil }
        let pixels = CGSize(width: points.width * scale, height: points.height * scale)
        guard let url = closest(name, covering: wanted(name, pixels: pixels, detail: detail), variant: variant) else { return nil }
        var request = ImageRequest(url: url, priority: priority)
        request.imageID = cacheID(url, variant: variant)
        return ImagePipeline.shared.cache.containsData(for: request) ? nil : request
    }

    private static let prefetcher = ImagePrefetcher(destination: .diskCache)

    private static func make(_ url: URL, decode: CGSize, priority: ImageRequest.Priority,
                             blur: CGFloat, variant: String?) -> ImageRequest {
        // A file on this phone is already on disk: no second copy in the cache.
        var request = ImageRequest(url: url, priority: priority, options: url.isFileURL ? [.disableDiskCache] : [])
        if !url.isFileURL { request.imageID = cacheID(url, variant: variant) }
        // Aspect fill: the copy covers the frame whatever its proportions; then cropped to it, so memory
        // never keeps the edges the frame hides.
        request.thumbnail = .init(size: decode, unit: .pixels, contentMode: .aspectFill)
        var processors: [any ImageProcessing] = [.resize(size: decode, unit: .pixels, contentMode: .aspectFill, crop: true)]
        if blur > 0 { processors.append(.gaussianBlur(radius: max(1, Int(blur * max(decode.width, decode.height))))) }
        request.processors = processors
        return request
    }

    /// The caches' key: the object and width, whatever the signature.
    private static func cacheID(_ url: URL, variant: String?) -> String {
        let key = MediaURL.canonical(url).absoluteString
        return variant.map { "\(key)#\($0)" } ?? key
    }

    // MARK: Copies served by the media Worker

    /// The width to download for a frame of `pixels` (`Renditions.wanted`), on the line as it is now.
    private static func wanted(_ name: String, pixels: CGSize, detail: Bool) -> CGFloat {
        Renditions.wanted(for: pixels, aspect: MediaPreviews.aspect(for: name), detail: detail,
                          slow: NetworkQuality.shared.isSlow)
    }

    /// The copy to show for `needed` pixels of width: the first of `Renditions.candidates` already on this
    /// phone (a larger copy beats a download), otherwise the one covering it.
    private static func closest(_ name: String, covering needed: CGFloat, variant: String?) -> URL? {
        let candidates = Renditions.candidates(covering: needed)
        for width in candidates {
            if let url = onDisk(name, width: width, variant: variant) { return url }
        }
        return sized(name, width: candidates[0])
    }

    /// The link to the copy `width` wide (nil: the original) when it's on this phone.
    private static func onDisk(_ name: String, width: Int?, variant: String?) -> URL? {
        guard let url = sized(name, width: width) else { return nil }
        var probe = ImageRequest(url: url)
        probe.imageID = cacheID(url, variant: variant)
        return ImagePipeline.shared.cache.containsData(for: probe) ? url : nil
    }

    /// A photo link with `&w=` set to `width` (nil: the original). Only a signed link goes through the
    /// media Worker, which serves the widths; any other is left as it is. `w` isn't part of the
    /// signature, and the caches keep one copy per width (`MediaURL.canonical`).
    static func sized(_ name: String, width: Int?) -> URL? {
        guard let url = URL(string: name) else { return nil }
        guard MediaURL.key(of: url) != nil, MediaURL.expiry(of: url) != nil,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (parts.queryItems ?? []).filter { $0.name != "w" }
        if let width { items.append(URLQueryItem(name: "w", value: String(width))) }
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
        // Leaves Nuke's queue now: how fast it arrives tells how fast the line is.
        var (didReceiveData, completion) = NetworkQuality.shared.measure(request.url, didReceiveData, completion)
        #if DECK_PHOTO_METRICS
        (didReceiveData, completion) = DeckPhotoMetrics.observe(request.url, didReceiveData, completion)
        #endif
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
