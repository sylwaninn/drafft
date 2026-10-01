import CoreImage
import UIKit

/// One like on the free plan: what the server gives without drafft tempo (`liked_me`, backend
/// 20260928000231), an opaque handle, whether it was a super like, when, a ThumbHash of the first
/// photo and, when the backend has made one, a signed link to a blurred copy of that photo
/// (`blurUrl`). Nobody's id, name or sharp photo reaches the phone: the blur is the server's, not a
/// filter here.
struct BlurredLike: Identifiable, Equatable {
    let id: String
    let superLike: Bool
    /// When they liked you (the server's `likedAt`). Nil if it didn't send one: no age label then.
    let likedAt: Date?
    /// The ThumbHash (about 32 × 32 px) drawn smooth at tile size, once, when the list is read. Nil: a
    /// night tile stands in. Also the placeholder and the fallback of `blurURL`.
    let preview: UIImage?
    /// Signed link to the server's blurred rendition of the first photo. Nil from a backend that
    /// doesn't send it yet, or when there is none: the ThumbHash alone.
    let blurURL: String?

    static func == (a: BlurredLike, b: BlurredLike) -> Bool {
        a.id == b.id && a.superLike == b.superLike && a.likedAt == b.likedAt && a.blurURL == b.blurURL
    }

    /// Same like, same look: only the link's signature may differ (it's renewed on every read).
    func sameLike(as other: BlurredLike) -> Bool {
        id == other.id && superLike == other.superLike && likedAt == other.likedAt
            && blurURL.flatMap(URL.init(string:)).map(MediaURL.canonical)
            == other.blurURL.flatMap(URL.init(string:)).map(MediaURL.canonical)
    }
}

extension BlurredLike {
    private struct Row: Decodable {
        let likeId: String
        let superLike: Bool
        let likedAt: String?
        let thumbhash: String?
        let blurUrl: String?
    }

    /// `liked_me` as a free account gets it (`AppModel.loadLikes`): previews decoded off the main actor.
    /// Nil if it isn't that shape.
    static func list(from data: Data) async -> [BlurredLike]? {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let likes = rows.map { row in
                BlurredLike(id: row.likeId, superLike: row.superLike,
                            likedAt: row.likedAt.flatMap { try? ServerDate.parse($0) },
                            preview: row.thumbhash.flatMap(ThumbHash.image(fromBase64:)).map(frosted),
                            blurURL: row.blurUrl.flatMap { $0.hasPrefix("http") ? $0 : nil })
            }
            return LikeOrder.newestFirst(likes, date: \.likedAt, id: \.id)
        }.value
    }

    /// Built once: a CIContext per call costs tens of milliseconds.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// The preview scaled up six times and softened, so a 32 px hash reads as frosted glass on a
    /// 250 pt tile instead of showing its pixels. It adds no detail: the hash is all there is.
    private static func frosted(_ hash: CGImage) -> UIImage {
        let scale: CGFloat = 6
        let extent = CGRect(x: 0, y: 0, width: CGFloat(hash.width) * scale, height: CGFloat(hash.height) * scale)
        let image = CIImage(cgImage: hash)
            .clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .applyingGaussianBlur(sigma: Double(scale) * 0.8)
            .cropped(to: extent)
        guard let out = context.createCGImage(image, from: extent) else { return UIImage(cgImage: hash) }
        return UIImage(cgImage: out)
    }
}
