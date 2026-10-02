import Foundation
import os

/// The silent moderation check of a photo or video sent in a chat, once it's on the media bucket: the
/// backend's chat-media function judges it (Rekognition; a video by its poster). Nothing changes on
/// screen; a flagged one is recorded server-side (media_flags).
enum ChatMediaCheck {
    private static let log = AppLog("chat-media")

    /// Logged: whether it was flagged, or why the check couldn't run (offline, no session).
    static func check(key: String, posterKey: String? = nil) async {
        do {
            var body = ["key": key]
            if let posterKey { body["posterKey"] = posterKey }
            let response = try await Backend.shared.function("chat-media", body)
            struct Verdict: Decodable { let flagged: Bool }
            let flagged = try JSONDecoder().decode(Verdict.self, from: response).flagged
            log.info("chat media \(key): \(flagged ? "flagged" : "clean")")
        } catch {
            log.error("chat media check failed: \(error.localizedDescription)")
        }
    }
}
