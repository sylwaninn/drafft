import UIKit

/// One like on the free plan: what the server gives without drafft tempo (`liked_me`, backend
/// 20260928000231), an opaque handle, whether it was a super like, when, and a ThumbHash of the first
/// photo. Nobody's id, name or photo reaches the phone: the blur is the server's, not a filter here.
struct BlurredLike: Identifiable, Equatable {
    let id: String
    let superLike: Bool
    /// About 32 × 32 px, decoded once when the list is read. Nil: a sage tile stands in.
    let preview: UIImage?

    static func == (a: BlurredLike, b: BlurredLike) -> Bool { a.id == b.id && a.superLike == b.superLike }
}

extension BlurredLike {
    private struct Row: Decodable {
        let likeId: String
        let superLike: Bool
        let thumbhash: String?
    }

    /// `liked_me` as a free account gets it (`AppModel.loadLikes`): previews decoded off the main actor.
    /// Nil if it isn't that shape.
    static func list(from data: Data) async -> [BlurredLike]? {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            rows.map { row in
                BlurredLike(id: row.likeId, superLike: row.superLike,
                            preview: row.thumbhash.flatMap(ThumbHash.image(fromBase64:)).map(UIImage.init(cgImage:)))
            }
        }.value
    }
}
