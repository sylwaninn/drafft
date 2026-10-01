import UIKit

/// The ThumbHash of each server photo the app knows (sent with its media row), turned into a blurred
/// preview the photo view draws while the real image loads, and its proportions, which decide the copy
/// to download (`Renditions`). Keyed by media key: a photo's link changes with its signature, its key
/// never does. Previews are decoded on first use (about 32 × 32 px) and cached with a bound; hashes are a
/// few dozen bytes each, capped too.
enum MediaPreviews {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var hashes: [String: String] = [:]
    /// Width over height, from the media row's size (or, without one, its ThumbHash).
    nonisolated(unsafe) private static var aspects: [String: CGFloat] = [:]
    /// NSCache is thread-safe.
    nonisolated(unsafe) private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()
    private static let hashLimit = 5_000

    /// Records a media row's hash (nil or empty: nothing to show) and size in pixels (nil: unknown).
    static func register(_ hash: String?, key: String, width: Int? = nil, height: Int? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let width, let height, width > 0, height > 0 {
            if aspects[key] == nil, aspects.count >= hashLimit { aspects.removeAll(keepingCapacity: true) }
            aspects[key] = CGFloat(width) / CGFloat(height)
        }
        guard let hash, !hash.isEmpty else { return }
        if hashes[key] == nil, hashes.count >= hashLimit { hashes.removeAll(keepingCapacity: true) }
        hashes[key] = hash
    }

    /// A server photo's width over its height: its row's size, or its preview's (a ThumbHash keeps the
    /// proportions); nil when neither is known.
    static func aspect(for name: String) -> CGFloat? {
        guard name.hasPrefix("http"), let url = URL(string: name), let key = MediaURL.key(of: url) else { return nil }
        lock.lock()
        let known = aspects[key]
        lock.unlock()
        if let known { return known }
        guard let preview = image(for: name), preview.size.height > 0 else { return nil }
        return preview.size.width / preview.size.height
    }

    /// The preview of a server photo (`http…`), if its hash is known.
    static func image(for name: String) -> UIImage? {
        guard name.hasPrefix("http"), let url = URL(string: name), let key = MediaURL.key(of: url) else { return nil }
        if let hit = images.object(forKey: key as NSString) { return hit }
        lock.lock()
        let hash = hashes[key]
        lock.unlock()
        guard let hash, let cg = ThumbHash.image(fromBase64: hash) else { return nil }
        let image = UIImage(cgImage: cg)
        images.setObject(image, forKey: key as NSString)
        return image
    }
}
