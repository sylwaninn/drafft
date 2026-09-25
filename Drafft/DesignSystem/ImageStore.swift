import UIKit
import CoreImage

/// Display-ready copies of the bundled photos.
///
/// A bundled JPEG (1000 to 1400 px) is decoded on the main thread the first time it's drawn.
/// A tab full of avatars did that dozens of times on its first visit, and the tab bar stopped
/// answering until it was done. Here small displays get a downsampled copy, blurred displays
/// get the blur baked in once (no live blur filter), and the photos the first screens need are
/// prepared in the background at launch.
enum ImageStore {
    // Both are thread-safe (NSCache, CIContext): used from the main thread and the prewarm.
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 160 * 1024 * 1024
        return c
    }()
    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Pixel sizes shared by nearby displays (a 56 pt and a 64 pt avatar use one copy).
    /// 0 means the full photo.
    private static func bucket(_ points: CGFloat?) -> Int {
        guard let points else { return 0 }
        let px = points * 3
        return [96, 192, 384, 768].first { CGFloat($0) >= px } ?? 0
    }

    /// The photo, sized for a display whose shorter side is `side` points (nil: full size).
    static func image(_ name: String, side: CGFloat? = nil) -> UIImage? {
        load(name, bucket: bucket(side), blur: 0)
    }

    /// Full-size photo only if it's already prepared (prewarmed): otherwise nil, and the view
    /// falls back to the system's lazy decode rather than decoding on the spot (a stack of
    /// hidden photos, like the welcome carousel, would all decode at once).
    static func preparedFull(_ name: String) -> UIImage? {
        cache.object(forKey: "\(name)@0b0" as NSString)
    }

    /// A small copy with the blur already applied (locked likes): drawn like any image.
    /// `fraction` is the blur radius as a share of the photo's shorter side, so it looks the
    /// same as a live `.blur(radius: fraction × side)` on screen.
    static func blurred(_ name: String, fraction: CGFloat) -> UIImage? {
        load(name, bucket: 192, blur: (192 * fraction).rounded())
    }

    /// Prepares photos off the main thread so the first screens draw them without decoding.
    static func prewarm(full: [String], small: [(name: String, side: CGFloat)],
                        blurred: [(name: String, fraction: CGFloat)]) {
        Task.detached(priority: .utility) {
            for name in full { _ = image(name) }
            for item in small { _ = image(item.name, side: item.side) }
            for item in blurred { _ = ImageStore.blurred(item.name, fraction: item.fraction) }
        }
    }

    // MARK: Making copies

    private static func load(_ name: String, bucket: Int, blur: CGFloat) -> UIImage? {
        let key = "\(name)@\(bucket)b\(Int(blur))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let made = make(name, bucket: bucket, blur: blur) else { return nil }
        let cost = Int(made.size.width * made.scale * made.size.height * made.scale * 4)
        cache.setObject(made, forKey: key, cost: cost)
        return made
    }

    private static func make(_ name: String, bucket: Int, blur: CGFloat) -> UIImage? {
        guard let source = UIImage(named: name) else { return nil }
        var image = source
        let shorter = min(source.size.width, source.size.height) * source.scale
        if bucket > 0, CGFloat(bucket) < shorter {
            let s = CGFloat(bucket) / shorter
            let size = CGSize(width: (source.size.width * source.scale * s).rounded(),
                              height: (source.size.height * source.scale * s).rounded())
            image = source.preparingThumbnail(of: size) ?? source
        }
        if blur > 0, let cg = image.cgImage {
            let input = CIImage(cgImage: cg)
            // Clamped so the edges don't fade to transparent, then cropped back.
            let output = input.clampedToExtent()
                .applyingGaussianBlur(sigma: Double(blur))
                .cropped(to: input.extent)
            if let blurred = context.createCGImage(output, from: input.extent) {
                return UIImage(cgImage: blurred)
            }
        }
        return image.preparingForDisplay() ?? image
    }
}
