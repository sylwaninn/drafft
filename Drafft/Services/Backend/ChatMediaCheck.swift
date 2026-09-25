import Foundation
import os

/// The silent moderation check of a chat photo: compressed, uploaded to the chat folder of the
/// media bucket, then judged by the backend's chat-media function (Rekognition). Nothing changes on
/// screen; a flagged photo is recorded server-side (media_flags).
enum ChatMediaCheck {
    private static let log = Logger(subsystem: "so.drafft.app", category: "chat-media")

    /// Whether the photo was flagged, or nil when the check couldn't run (offline, no session).
    @discardableResult
    static func photo(_ data: Data) async -> Bool? {
        do {
            let tickets = EdgeFunctionTicketProvider(functionsURL: BackendConfig.functionsURL) {
                try await Backend.shared.accessToken()
            }
            let uploaded = try await MediaUploads.photo(data, purpose: .chatPhoto, tickets: tickets)
            let response = try await Backend.shared.function("chat-media", ["key": uploaded.key])
            struct Verdict: Decodable { let flagged: Bool }
            let flagged = try JSONDecoder().decode(Verdict.self, from: response).flagged
            log.info("chat photo \(uploaded.key, privacy: .public): \(flagged ? "flagged" : "clean", privacy: .public)")
            return flagged
        } catch {
            log.error("chat photo check failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
