import UIKit

/// The ThumbHash of each server photo the app knows (sent with its media row), turned into a blurred
/// preview the photo view draws while the real image loads. Keyed by media key: a photo's link changes
/// with its signature, its key never does. Previews are decoded on first use (about 32 × 32 px) and
/// cached with a bound; hashes are a few dozen bytes each, capped too.
enum MediaPreviews {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var hashes: [String: String] = [:]
    /// NSCache is thread-safe.
    nonisolated(unsafe) private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()
    private static let hashLimit = 5_000

    /// Records a media row's hash (nil or empty: nothing to show).
    static func register(_ hash: String?, key: String) {
        guard let hash, !hash.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        if hashes[key] == nil, hashes.count >= hashLimit { hashes.removeAll(keepingCapacity: true) }
        hashes[key] = hash
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
