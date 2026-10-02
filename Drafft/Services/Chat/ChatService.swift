import Combine
import Foundation
import StreamChat
import SwiftUI
import UIKit
import os

extension ChatPayload.Media: AttachmentPayload {
    static let type: AttachmentType = "drafft_media"
}

/// The chat, on Stream (low-level client, drafft's own screens). One connection per signed-in account:
///
/// - Connection: `stream-token` gives the key and a 24 h token; the SDK asks for a new one through the
///   token provider before it expires, reconnects by itself (network, background), keeps an offline copy
///   (the last known chats show at launch) and catches up on reconnect.
/// - Chats: one per active match (`AppModel.matches`, read from `my_matches` and kept live by Realtime
///   `match` / `match_ended`, the source of truth: an ended match, whose channel the server froze, is gone
///   at once), joined with its Stream channel. The list and every open chat follow Stream's events live.
/// - Messages: optimistic (the SDK's local copy, then the server's). Media is uploaded to drafft's bucket
///   first (`media-upload-url`, purpose chat) and sent as a `drafft_media` attachment carrying the object's
///   key; links are signed on display (`media_urls`).
/// - Sessions live in Postgres (`sessions`, `SessionStore`): the chat carries one card per session, from
///   the channel's `drafft.type: "session"` message, showing the live row.
@MainActor
final class ChatService {
    static let shared = ChatService()
    let log = AppLog("chat")
    /// Messages read at a time with each chat: a chat opens on its latest ones.
    static let messagesPage = 25

    /// A media message that can't be sent: not the account's own objects, or the chat is gone.
    struct SendRefused: Error {}

    weak var app: AppModel?
    var client: ChatClient?
    var apiKey: String?
    /// The account connected (or connecting), lowercased.
    private(set) var userID: String?
    var connecting: Task<Void, Never>?
    var connected = false
    var channelList: ChannelList?
    var observers: [AnyCancellable] = []

    var channels: [String: ChatChannel] = [:]
    /// Open chats: their whole loaded history, followed live.
    var chats: [String: Chat] = [:]
    var chatObservers: [String: [AnyCancellable]] = [:]
    var history: [String: [ChatMessage]] = [:]
    /// Invites sent from this device, shown until the channel's message for them arrives (by match).
    var pendingSessions: [String: [Message]] = [:]
    /// Session rows already asked for by a card.
    var requestedSessions: Set<UUID> = []
    /// Media being prepared and uploaded, and text written before the chat was connected: not yet a Stream
    /// message (by match).
    var uploads: [String: [Upload]] = [:]
    /// What this device sent (its own picture, video file, recording): shown instead of the downloaded copy.
    var localMedia: [String: MessageContent] = [:]
    /// Signed links by object key.
    var links: [String: (url: String, expires: Date?)] = [:]
    var signing: Set<String> = []
    /// Push token, kept until the client is connected.
    var deviceToken: Data?

    struct Upload {
        var message: Message
        let matchID: String
        let source: Source
        enum Source {
            case text(String), photo(Data), video(URL), voice(URL, TimeInterval, [Float])

            /// What kind of message it makes, for analytics.
            var telemetryKind: AnalyticsEvent.MessageKind {
                switch self {
                case .text: .text
                case .photo: .photo
                case .video: .video
                case .voice: .voice
                }
            }
        }
    }

    // MARK: Connection

    /// Signed in (launch, sign-in): connects once for the account, then keeps it up. Calling it again for
    /// the same account only shows the chats again.
    func start(_ app: AppModel) async {
        self.app = app
        guard let me = await Backend.shared.userID?.uuidString.lowercased() else { return }
        if userID == me {
            publish()
            return
        }
        if userID != nil { await stop() }
        userID = me
        publish()
        connecting = Task { await connect(me) }
    }

    /// Signed out or account deleted: disconnects, forgets this device's push registration and the offline
    /// copy, so the next account on this iPhone starts empty.
    func stop() async {
        connecting?.cancel()
        connecting = nil
        observers = []
        chatObservers = [:]
        chats = [:]
        history = [:]
        channels = [:]
        pendingSessions = [:]
        requestedSessions = []
        uploads = [:]
        localMedia = [:]
        links = [:]
        channelList = nil
        userID = nil
        connected = false
        publish()
        if let client { await client.logout() }
    }

    func connect(_ me: String) async {
        var pause = Duration.seconds(2)
        while !Task.isCancelled, userID == me, !connected {
            do {
                let first = try await Self.fetchToken()
                let client = client(for: first.apiKey)
                let tokens = TokenSource(first: first.token)
                try await client.connectUser(userInfo: UserInfo(id: me)) { completion in
                    Task { completion(await tokens.next()) }
                }
                guard userID == me, !Task.isCancelled else { return }
                connected = true
                sendWaitingTexts()
                try await watchChannels(client, me: me)
                if let deviceToken { addDevice(deviceToken) }
            } catch {
                log.error("chat connect failed: \(error.localizedDescription)")
                Telemetry.unexpected(error, "chat", "connect")
                try? await Task.sleep(for: pause)
                pause = min(pause * 2, .seconds(60))
            }
        }
    }

    /// One client per Stream app (the key comes with the token, per environment).
    func client(for key: String) -> ChatClient {
        if let client, apiKey == key { return client }
        var config = ChatClientConfig(apiKeyString: key)
        config.isLocalStorageEnabled = true
        config.staysConnectedInBackground = true
        // Enough of each chat for the list and the first screen of a thread.
        config.localCaching.chatChannel.latestMessagesLimit = Self.messagesPage
        let made = ChatClient(config: config)
        client = made
        apiKey = key
        return made
    }

    struct StreamToken: Decodable, Sendable {
        let apiKey: String
        let userId: String
        let token: String
    }

    nonisolated static func fetchToken() async throws -> StreamToken {
        let data = try await Backend.shared.function("stream-token", [:])
        return try JSONDecoder().decode(StreamToken.self, from: data)
    }

    /// The first token (already fetched to learn the key), then a fresh one each time the SDK asks.
    private actor TokenSource {
        private var first: String?
        init(first: String) { self.first = first }
        func next() async -> Result<Token, Error> {
            do {
                if let token = first {
                    first = nil
                    return .success(try Token(rawValue: token))
                }
                return .success(try Token(rawValue: try await ChatService.fetchToken().token))
            } catch {
                return .failure(error)
            }
        }
    }

    func watchChannels(_ client: ChatClient, me: String) async throws {
        let query = ChannelListQuery(
            filter: .and([.containMembers(userIds: [me]), .equal(.frozen, to: false)]),
            sort: [.init(key: .lastMessageAt, isAscending: false)],
            pageSize: 30,
            messagesLimit: Self.messagesPage
        )
        // Local filter for channels arriving by events: a frozen one (match ended) or one left leaves the list.
        let list = client.makeChannelList(with: query) { !$0.isFrozen && $0.membership != nil }
        channelList = list
        observers = [
            list.state.$channels.sink { [weak self] in self?.channelsChanged($0) },
            client.subscribe(toEvent: MessageNewEvent.self) { [weak self] event in
                let matchID = event.cid.id, message = event.message
                Task { @MainActor in self?.received(message, in: matchID) }
            },
            client.subscribe(toEvent: ConnectionStatusUpdated.self) { [weak self] event in
                guard event.connectionStatus == .connected else { return }
                // Back online: matches and sessions may have changed meanwhile (Stream catches up by itself).
                Task { @MainActor in await self?.refresh() }
            }
        ]
        try await list.get()
        // Every chat, not just the first page: a person has few enough matches.
        for _ in 0..<20 where list.state.channels.count >= 30 {
            let more = try await list.loadMoreChannels(limit: 30)
            if more.count < 30 { break }
        }
    }

    // MARK: Push

    /// The APNs token: Stream pushes messages to it, through the provider of this build's APNs environment.
    func registerDevice(_ token: Data) {
        deviceToken = token
        if connected { addDevice(token) }
    }

    func addDevice(_ token: Data) {
        guard let client else { return }
        let provider = PushEnvironment.current == "sandbox" ? "drafft-apn-dev" : "drafft-apn"
        client.currentUserController().addDevice(.apn(token: token, providerName: provider)) { [log] error in
            if let error { log.error("chat push device: \(error.localizedDescription)") }
        }
    }

    // MARK: Matches and sessions

    /// Matches and sessions read again (Stream reconnected): the chats follow the matches.
    func refresh() async {
        await app?.loadMatches()
        await SessionStore.shared.refresh()
        publish()
    }

    /// An invite sent from this device: its card shows at once (`SessionStore` has its row).
    func showPending(_ proposal: SessionProposal, in matchID: String) {
        pendingSessions[matchID, default: []].append(Message(.session(proposal), fromMe: true, state: .sending))
        publish()
    }

    /// The server refused it: its card goes.
    func dropPending(_ sessionID: UUID, in matchID: String) {
        pendingSessions[matchID]?.removeAll { m in
            if case .session(let s) = m.content { return s.id == sessionID }
            return false
        }
        publish()
    }

    // MARK: Open chats

    /// A chat on screen: its whole history (older pages on demand), live.
    func open(_ matchID: String) {
        guard let client, chats[matchID] == nil else { return }
        let chat = client.makeChat(for: ChannelId(type: .messaging, id: matchID), messageOrdering: .bottomToTop)
        chats[matchID] = chat
        chatObservers[matchID] = [
            chat.state.$messages.sink { [weak self] messages in
                self?.history[matchID] = messages
                self?.publish()
            },
            chat.state.$channel.sink { [weak self] channel in
                guard let channel else { return }
                self?.channels[matchID] = channel
                self?.publish()
            }
        ]
        Task {
            try? await chat.watch()
            await markRead(matchID)
        }
    }

    func close(_ matchID: String) {
        chatObservers[matchID] = nil
        chats[matchID] = nil
        history[matchID] = nil
        Task { try? await self.chat(matchID)?.stopTyping() }
        publish()
    }

    /// Scrolled to the top of a thread: the page before.
    func loadOlder(_ matchID: String) {
        guard let chat = chats[matchID] else { return }
        Task {
            guard await !chat.state.hasLoadedAllOldestMessages else { return }
            try? await chat.loadOlderMessages(limit: 30)
        }
    }

    func chat(_ matchID: String) -> Chat? {
        if let chat = chats[matchID] { return chat }
        return client?.makeChat(for: ChannelId(type: .messaging, id: matchID))
    }

    // MARK: Actions

    /// Sends at once (the bubble shows before the server has it). Text goes straight to Stream; photos,
    /// videos and voice messages are uploaded to drafft's bucket first, then sent with their key.
    func send(_ content: MessageContent, in matchID: String, replyTo: String?) {
        let id = UUID().uuidString.lowercased()
        switch content {
        case .text(let text):
            // Not connected yet (just launched offline): the bubble shows as sending and goes once the chat
            // connects, never dropped. Connected, Stream keeps its own copy and resends it.
            startUpload(Upload(message: Message(id: id, content, fromMe: true, state: .sending, replyTo: replyTo),
                               matchID: matchID, source: .text(text)))
        case .photo(_, let data?):
            startUpload(Upload(message: pendingMessage(id, content, replyTo), matchID: matchID, source: .photo(data)))
        case let .video(url, _, _):
            startUpload(Upload(message: pendingMessage(id, content, replyTo), matchID: matchID, source: .video(url)))
        case let .voice(url, duration, levels):
            startUpload(Upload(message: pendingMessage(id, content, replyTo), matchID: matchID,
                               source: .voice(url, duration, levels)))
        case .session(let proposal):
            app?.proposeSession(proposal, in: matchID)
        default:
            break
        }
    }

    func pendingMessage(_ id: String, _ content: MessageContent, _ replyTo: String?) -> Message {
        localMedia[id] = content
        return Message(id: id, content, fromMe: true, state: .sending, replyTo: replyTo)
    }

    func startUpload(_ upload: Upload) {
        uploads[upload.matchID, default: []].removeAll { $0.message.id == upload.message.id }
        var upload = upload
        upload.message.state = .sending
        uploads[upload.matchID, default: []].append(upload)
        publish()
        let tickets = EdgeFunctionTicketProvider(functionsURL: BackendConfig.functionsURL) {
            try await Backend.shared.accessToken()
        }
        if case .text(let text) = upload.source {
            sendText(text, upload)
            return
        }
        let kind = upload.source.telemetryKind
        Task {
            do {
                // Timed (Sentry Performance): compression and upload, the slow part of a media message.
                let uploaded: ChatPayload.Media? = try await Telemetry.trace("media.upload", "chat \(kind.rawValue)") { _ in
                    switch upload.source {
                    case .text: return nil
                    case .photo(let data):
                        let sent = try await MediaUploads.photo(data, purpose: .chatPhoto, tickets: tickets)
                        return ChatPayload.Media(kind: .photo, key: sent.key, width: sent.width, height: sent.height,
                                                 thumbhash: sent.thumbHash)
                    case .video(let url):
                        let sent = try await MediaUploads.video(url, purpose: .chatVideo, settings: .chat,
                                                                posterPurpose: .chatPhoto, tickets: tickets)
                        return ChatPayload.Media(kind: .video, key: sent.key, width: sent.width, height: sent.height,
                                                 duration: sent.duration, posterKey: sent.posterKey, thumbhash: sent.thumbHash)
                    case let .voice(url, duration, levels):
                        let key = try await MediaUploads.voice(url, purpose: .chatVoice, tickets: tickets)
                        return ChatPayload.Media(kind: .voice, key: key, duration: duration,
                                                 levels: Self.compact(levels))
                    }
                }
                guard let media = uploaded else { return }
                // Only the person's own chat objects are ever sent (keys, never links).
                guard let me = userID, ChatPayload.Media.isOwnChatKey(media.key, userID: me),
                      media.posterKey.map({ ChatPayload.Media.isOwnChatKey($0, userID: me) }) ?? true,
                      let chat = chat(upload.matchID) else { throw SendRefused() }
                try await chat.sendMessage(with: "", attachments: [AnyAttachmentPayload(payload: media)],
                                           quote: upload.message.replyTo, messageId: upload.message.id)
                uploads[upload.matchID]?.removeAll { $0.message.id == upload.message.id }
                publish()
                // Photos and videos get the silent check (flagged ones are only recorded server-side).
                if media.kind != .voice { Task { await ChatMediaCheck.check(key: media.key, posterKey: media.posterKey) } }
            } catch {
                log.error("media send failed: \(error.localizedDescription)")
                Telemetry.track(.messageFailed(kind, reason: Telemetry.reason(error)))
                Telemetry.unexpected(error, "chat", "send_media", extra: ["kind": kind])
                if let i = uploads[upload.matchID]?.firstIndex(where: { $0.message.id == upload.message.id }) {
                    uploads[upload.matchID]?[i].message.state = .failed
                    publish()
                }
            }
        }
    }

    /// A text, handed to Stream once it can take it (written before the chat connected, it waits). Stream's
    /// own copy, with the same id, replaces this bubble as soon as it exists.
    func sendText(_ text: String, _ upload: Upload) {
        guard connected, let chat = chat(upload.matchID) else { return }
        Task {
            do {
                try await chat.sendMessage(with: text, quote: upload.message.replyTo, messageId: upload.message.id)
                uploads[upload.matchID]?.removeAll { $0.message.id == upload.message.id }
            } catch {
                // Stream's copy (same id) shows as failed with its retry; without one, this bubble does.
                log.error("send failed: \(error.localizedDescription)")
                Telemetry.track(.messageFailed(.text, reason: Telemetry.reason(error)))
                Telemetry.unexpected(error, "chat", "send_text")
                if let i = uploads[upload.matchID]?.firstIndex(where: { $0.message.id == upload.message.id }) {
                    uploads[upload.matchID]?[i].message.state = .failed
                }
            }
            publish()
        }
    }

    /// Connected: the texts written while it wasn't go now, in the order they were written.
    func sendWaitingTexts() {
        for upload in uploads.values.joined() {
            if case .text(let text) = upload.source { sendText(text, upload) }
        }
    }

    /// A voice message's waveform, at most 60 bars (the attachment stays small).
    static func compact(_ levels: [Float]) -> [Float] {
        guard levels.count > 60 else { return levels }
        let step = Double(levels.count) / 60
        return (0..<60).map { levels[min(levels.count - 1, Int(Double($0) * step))] }
    }

    /// A message that couldn't be sent, sent again.
    func retry(_ messageID: String, in matchID: String) {
        if let upload = uploads[matchID]?.first(where: { $0.message.id == messageID }) {
            startUpload(upload)
        } else if let chat = chat(matchID) {
            Task { try? await chat.resendMessage(messageID) }
        }
    }

    /// Your reaction on one of their messages (never your own), one per person: a new one replaces it,
    /// the same one again removes it.
    func react(_ emoji: String?, to messageID: String, current: String?, in matchID: String) {
        guard let chat = chat(matchID) else { return }
        Task {
            if let current, emoji == nil || emoji == current {
                try? await chat.deleteReaction(from: messageID, with: MessageReactionType(rawValue: current))
            } else if let emoji {
                try? await chat.sendReaction(to: messageID, with: MessageReactionType(rawValue: emoji), enforceUnique: true)
            }
        }
    }

    /// Unsend one of your messages (an upload not sent yet just stops).
    func delete(_ messageID: String, in matchID: String) {
        if uploads[matchID]?.contains(where: { $0.message.id == messageID }) == true {
            uploads[matchID]?.removeAll { $0.message.id == messageID }
            publish()
            return
        }
        guard let chat = chat(matchID) else { return }
        Task { try? await chat.deleteMessage(messageID) }
    }

    func markRead(_ matchID: String) async {
        guard let channel = channels[matchID], channel.unreadCount.messages > 0 || channel.isUnread else { return }
        try? await chat(matchID)?.markRead()
    }

    /// "Mark as unread": from their last message, as Stream counts it (on every device).
    func markUnread(_ matchID: String) {
        guard let last = (history[matchID] ?? channels[matchID]?.latestMessages ?? [])
            .filter({ !$0.isSentByCurrentUser }).max(by: { $0.createdAt < $1.createdAt }) else { return }
        Task { try? await chat(matchID)?.markUnread(from: last.id) }
    }

    /// Typing: tells the other person (the SDK spaces the events out and stops them after a pause).
    func typing(in matchID: String, text: String) {
        guard let chat = chats[matchID] else { return }
        Task {
            if text.isEmpty { try? await chat.stopTyping() } else { try? await chat.keystroke() }
        }
    }

    func toggleMute(_ matchID: String) {
        guard let chat = chat(matchID), let channel = channels[matchID] else { return }
        let muted = channel.isMuted
        Task {
            if muted { try? await chat.unmute() } else { try? await chat.mute() }
        }
    }

    // MARK: Events

    /// A message arrived. From the other person, while that chat isn't on screen: a banner (the server's
    /// own messages, openers and sessions, come with their own push).
    func received(_ message: ChatMessage, in matchID: String) {
        guard !message.isSentByCurrentUser, let app, let match = app.matches.first(where: { $0.id == matchID }) else { return }
        let onScreen = app.openChatID == matchID && UIApplication.shared.applicationState == .active
        if onScreen {
            Haptics.tap()
            Task { await markRead(matchID) }
            return
        }
        guard message.extraData["drafft"] == nil, let mapped = map(message, in: matchID) else { return }
        let profile = match.profile
        let muted = channels[matchID]?.isMuted ?? false
        Task {
            await NotificationService.shared.notify(.message, from: profile.firstName, photo: profile.portrait,
                                                    chatID: matchID, muted: muted, preview: mapped.previewText)
        }
    }

    func channelsChanged(_ list: [ChatChannel]) {
        for channel in list { channels[channel.cid.id] = channel }
        let ids = Set(list.map(\.cid.id))
        // Left or frozen since (match ended): not shown, even before `my_matches` says so.
        for id in channels.keys where !ids.contains(id) && chats[id] == nil { channels[id] = nil }
        publish()
    }
}
