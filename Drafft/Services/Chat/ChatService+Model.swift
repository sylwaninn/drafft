import Foundation
import StreamChat

/// The chats as the app shows them: Stream's channels and messages, the matches' profiles, the sessions'
/// rows and the signed media links, turned into `Conversation`s and `Message`s.
extension ChatService {
    // MARK: Building the app's model

    /// The chats as the app shows them, in order: latest activity first.
    func publish() {
        guard let app else { return }
        var conversations: [Conversation] = []
        var sessionsByChat: [String: [SessionProposal]] = [:]
        var missingSessions: Set<UUID> = []
        for (matchID, match) in matches {
            if let channel = channels[matchID], channel.isFrozen { continue }
            let profile = match.profile.profile
            let channel = channels[matchID]
            var messages = (history[matchID] ?? channel?.latestMessages ?? [])
                .compactMap { m -> Message? in
                    if case .session(let id)? = sessionReference(m), sessions[id] == nil { missingSessions.insert(id) }
                    return map(m, in: matchID)
                }
            let sent = Set(messages.map(\.id))
            messages += (uploads[matchID] ?? []).map(\.message).filter { !sent.contains($0.id) }
            messages.sort { $0.date < $1.date }
            let old = app.conversation(matchID)
            let other = channel?.lastActiveMembers.first { $0.id != userID }
            var convo = Conversation(
                id: matchID, profile: profile, messages: messages,
                isTyping: channel?.currentlyTypingUsers.contains { $0.id != userID } ?? false,
                unread: app.openChatID == matchID ? 0 : channel?.unreadCount.messages ?? 0,
                matchedAt: match.matchedAt, muted: channel?.isMuted ?? false)
            convo.markedUnread = (old?.markedUnread ?? false) && app.openChatID != matchID
            convo.online = other?.isOnline ?? false
            conversations.append(convo)
            sessionsByChat[matchID] = sessions.values.filter { $0.matchID == matchID }.map { $0.proposal(me: userID) }
        }
        conversations.sort { ($0.lastMessage?.date ?? $0.matchedAt) > ($1.lastMessage?.date ?? $1.matchedAt) }
        if app.conversations != conversations { app.conversations = conversations }
        if app.chatSessions != sessionsByChat { app.chatSessions = sessionsByChat }
        if !missingSessions.isEmpty {
            Task {
                await loadSessions(ids: Array(missingSessions))
                publish()
            }
        }
    }

    func sessionReference(_ m: ChatMessage) -> ChatPayload.Kind? {
        guard let extra = Self.extra(m) else { return nil }
        return ChatPayload.kind(text: m.text, extra: extra)
    }

    static func extra(_ m: ChatMessage) -> ChatPayload.Extra? {
        guard let raw = m.extraData["drafft"], let data = try? JSONEncoder().encode(raw) else { return nil }
        return try? JSONDecoder().decode(ChatPayload.Extra.self, from: data)
    }

    /// One Stream message as the thread shows it, or nil (deleted, system, a session's later status).
    func map(_ m: ChatMessage, in matchID: String) -> Message? {
        guard m.type != .system, m.type != .error, m.type != .deleted, m.type != .ephemeral,
              m.deletedAt == nil, !m.isShadowed else { return nil }
        let fromMe = m.isSentByCurrentUser
        var message: Message
        if let media = m.attachments(payloadType: ChatPayload.Media.self).first?.payload {
            message = Message(id: m.id, localMedia[m.id] ?? content(of: media), fromMe: fromMe, date: m.createdAt)
            if let w = media.width, let h = media.height { message.mediaSize = .init(width: Double(w), height: Double(h)) }
            message.poster = media.posterKey.flatMap(link)
        } else {
            guard let content = content(of: m, in: matchID) else { return nil }
            message = Message(id: m.id, content, fromMe: fromMe, date: m.createdAt)
        }
        message.state = state(of: m, in: matchID)
        message.reaction = m.latestReactions.first { $0.author.id != m.author.id }?.type.rawValue
        if let quoted = m.quotedMessage {
            message.replyTo = quoted.id
            message.replyQuote = (quoted.isSentByCurrentUser, map(quoted, in: matchID)?.previewText ?? quoted.text)
        }
        return message
    }

    /// A message without media: text, a session card, an opener; nil when it isn't shown.
    func content(of m: ChatMessage, in matchID: String) -> MessageContent? {
        switch ChatPayload.kind(text: m.text, extra: Self.extra(m)) {
        case .text(let text):
            return text.isEmpty ? nil : .text(text)
        case .session(let id):
            return sessions[id].map { .session($0.proposal(me: userID)) }
        case let .icebreakerReply(quote, reply):
            return .icebreakerReply(quote: quote, reply: reply)
        case let .photoReply(key, reply):
            return .photoReply(asset: matches[matchID]?.profile.link(forKey: key) ?? link(key) ?? "", reply: reply)
        case .hidden:
            return nil
        }
    }

    func state(of m: ChatMessage, in matchID: String) -> DeliveryState {
        switch m.localState {
        case .pendingSend, .sending: return .sending
        case .sendingFailed: return .failed
        default: break
        }
        guard m.isSentByCurrentUser else { return .read }
        let read = channels[matchID]?.reads.first { $0.user.id != userID }
        if let read, read.lastReadAt >= m.createdAt { return .read }
        if let delivered = read?.lastDeliveredAt, delivered >= m.createdAt { return .delivered }
        return .sent
    }

    func content(of media: ChatPayload.Media) -> MessageContent {
        let url = link(media.key)
        switch media.kind {
        case .photo:
            return .photo(asset: url, imageData: nil)
        case .video:
            return .video(url: url.flatMap(URL.init(string:)) ?? Self.unsigned, thumbnail: nil, duration: media.duration ?? 0)
        case .voice:
            return .voice(url: url.flatMap(URL.init(string:)) ?? Self.unsigned, duration: media.duration ?? 0,
                          levels: media.levels ?? [])
        }
    }

    /// Stands for a link not signed yet (asked for, it replaces this in a moment).
    static let unsigned = URL(string: "about:blank")!

    /// The signed link of an object, while it has more than a minute left; otherwise asked for (in one
    /// request with the others missing), and the thread updates when it comes.
    func link(_ key: String) -> String? {
        if let known = links[key], (known.expires ?? .distantFuture).timeIntervalSinceNow > 60 { return known.url }
        guard !signing.contains(key) else { return links[key]?.url }
        signing.insert(key)
        Task { await sign() }
        return links[key]?.url
    }

    func sign() async {
        // Let the rest of this pass ask too: one request for all of them.
        await Task.yield()
        let keys = Array(signing.prefix(100))
        guard !keys.isEmpty else { return }
        let signed = await MediaURL.signed(keys)
        for key in keys {
            signing.remove(key)
            if let url = signed[key] {
                links[key] = (url, URL(string: url).flatMap(MediaURL.expiry(of:)))
            }
        }
        if !signed.isEmpty { publish() }
    }
}

// MARK: - Sessions

/// A row of `sessions`, as PostgREST sends it.
struct SessionRow: Decodable, Hashable {
    let id: UUID
    let matchID: String
    let proposerID: String
    let sportID: String
    var options: [Date]
    var chosenAt: Date?
    let title: String
    let note: String
    let tags: [String]
    let discovery: String?
    var status: String

    static let columns = "id,match_id,proposer_id,sport_id,options,chosen_at,title,note,tags,discovery,status"

    enum CodingKeys: String, CodingKey {
        case id, options, title, note, tags, discovery, status
        case matchID = "match_id", proposerID = "proposer_id", sportID = "sport_id", chosenAt = "chosen_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        matchID = try c.decode(String.self, forKey: .matchID).lowercased()
        proposerID = try c.decode(String.self, forKey: .proposerID).lowercased()
        sportID = try c.decode(String.self, forKey: .sportID)
        options = try c.decode([String].self, forKey: .options).compactMap(ServerDate.parse)
        chosenAt = try c.decodeIfPresent(String.self, forKey: .chosenAt).flatMap(ServerDate.parse)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        discovery = try c.decodeIfPresent(String.self, forKey: .discovery)
        status = try c.decode(String.self, forKey: .status)
    }

    static func decode(_ data: Data) -> [SessionRow]? { try? JSONDecoder().decode([SessionRow].self, from: data) }
    static func decodeOne(_ data: Data) -> SessionRow? { try? JSONDecoder().decode(SessionRow.self, from: data) }

    func proposal(me: String?) -> SessionProposal {
        var p = SessionProposal(sport: Sport(rawValue: sportID) ?? .running, options: options, chosen: chosenAt,
                                title: title, note: note, tags: tags,
                                discovery: discovery == "iTeach" ? .iTeach : discovery == "theyTeach" ? .theyTeach : nil,
                                status: SessionProposal.Status(rawValue: status) ?? .pending)
        p.id = id
        p.mine = proposerID == me
        return p
    }
}

/// Timestamps as the server writes them (`2026-10-01T07:00:00+00:00`, with or without fractions).
enum ServerDate {
    nonisolated static func parse(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: text) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    nonisolated static func string(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
