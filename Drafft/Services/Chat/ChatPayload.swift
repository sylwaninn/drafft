import Foundation

/// What drafft puts in a chat message besides its text, independent of the chat SDK (unit tested).
///
/// - `drafft` (message extra data): the server's messages. `session` points to a row of `sessions`
///   (the card shows its live status), `superLikeNote` is the note sent with a super like, and the
///   openers attached to a like: `text`, `icebreakerReply` (`quote`), `photoReply` (`key`).
/// - `drafft_media` (attachment): a photo, video or voice message on drafft's media bucket. It holds the
///   object's KEY, never a link: the bucket is private, and each device asks the backend for a signed
///   link (`media_urls`, only between the two members of an active match) when it shows it.
enum ChatPayload {
    /// The `drafft` object of a message, as the backend writes it (db-events).
    struct Extra: Codable, Hashable {
        var type: String
        var sessionId: String?
        var status: String?
        var quote: String?
        var reply: String?
        var text: String?
        /// photoReply: the liked photo's key.
        var key: String?
    }

    /// How a message shows in the thread.
    enum Kind: Equatable {
        case text(String)
        /// The card of a session; only its proposal is shown (its later statuses update that card).
        case session(id: UUID)
        case icebreakerReply(quote: String, reply: String)
        case photoReply(key: String, reply: String)
        /// Not shown in the thread: a session's later status (the card says it), or something unknown.
        case hidden
    }

    static func kind(text: String, extra: Extra?) -> Kind {
        guard let extra else { return .text(text) }
        switch extra.type {
        case "session":
            guard let id = extra.sessionId.flatMap(UUID.init(uuidString:)) else { return .hidden }
            return extra.status == nil || extra.status == "proposed" ? .session(id: id) : .hidden
        case "icebreakerReply":
            return .icebreakerReply(quote: extra.quote ?? "", reply: extra.reply ?? text)
        case "photoReply":
            guard let key = extra.key, !key.isEmpty else { return .text(extra.reply ?? text) }
            return .photoReply(key: key, reply: extra.reply ?? text)
        case "superLikeNote", "text":
            return .text(extra.text ?? text)
        default:
            // A newer kind this build doesn't know: its text, if it has one.
            return text.isEmpty ? .hidden : .text(text)
        }
    }

    /// A photo, video or voice message: the attachment's payload (type `drafft_media`).
    struct Media: Codable, Hashable, Sendable {
        enum Kind: String, Codable, Sendable { case photo, video, voice }
        var kind: Kind
        /// The object's key on the media bucket (`u/<owner>/chat/<uuid>.<ext>`).
        var key: String
        var width: Int?
        var height: Int?
        /// Seconds (video, voice).
        var duration: Double?
        /// Voice: the waveform, 0...1.
        var levels: [Float]?
        /// Video: its poster frame's key.
        var posterKey: String?
        var thumbhash: String?

        enum CodingKeys: String, CodingKey {
            case kind, key, width, height, duration, levels, thumbhash
            case posterKey = "poster_key"
        }

        /// Keys this attachment needs signed links for.
        var keys: [String] { [key] + [posterKey].compactMap { $0 } }

        /// A key the app may send: one of the person's own chat objects. Anything else is refused before
        /// it's sent (and the backend only signs chat keys between members of an active match).
        static func isOwnChatKey(_ key: String, userID: String) -> Bool {
            key.hasPrefix("u/\(userID.lowercased())/chat/") && !key.contains("..") && key.count <= 200
        }
    }
}
