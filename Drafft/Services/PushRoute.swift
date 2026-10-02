import Foundation

/// A tapped notification, read from its payload: what it was about (`kind`, a telemetry code) and where
/// it leads (`destination`). The one reading of every sender's payload, kept free of the app so it can be
/// unit-tested (PushRouteTests); `AppModel.follow` takes it there once the tabs are on screen.
///
/// What each sender puts next to `aps` (drafft-backend, `supabase/functions`):
/// - like (`like.received`): `kind` `like` or `super_like`, `tab` `likes`. Opens Likes.
/// - match (`match.created`): `kind` `match`, `match`. Opens the chat.
/// - session proposed, accepted, declined (`sessionEvent`): `match`, `session`, no `kind`. Opens the chat,
///   where its card is the latest message.
/// - session cancelled: `kind` `session_cancelled`, `match`, `session`; cancelled with its match
///   (`session.auto_cancelled`) carries no `match` (no chat any more): opens Sessions.
/// - session reminder: `kind` `session_reminder`, `match`, `session`. Opens the chat.
/// - reaction (`stream-webhook`): `match` only. Opens the chat.
/// - message (Stream's own push, `scripts/stream-push.ts`): `match`, and `stream` (`type` `message.new`,
///   `cid` `messaging:<match>`). Opens the chat.
/// - photo refused: `kind` `photo_refused`, `media`. Shows why, over the current screen.
/// - moderation (a decision, a hold, a selfie asked for): `kind` `moderation`. Discover: the app shows the
///   account's state on its own (a hold covers everything).
/// - weekly boost: `kind` `weekly_boost`. Opens Discover, where it's used.
/// - the app's own (a message from another chat while the app is open): `chatID`. Opens the chat.
///
/// Anything else (a kind this build doesn't know) opens its chat when it names one, else Discover.
struct PushRoute: Equatable, Sendable {
    /// Sent as `push_opened`'s and `push_received`'s `kind` (the Android app's codes too): never renamed.
    enum Kind: String, CaseIterable, Sendable {
        case message = "new_message"
        case reaction, like
        case superLike = "super_like"
        case match
        /// A session proposed, accepted or declined (the backend sends no `kind` for these).
        case sessionUpdate = "session"
        case sessionCancelled = "session_cancelled"
        case sessionReminder = "session_reminder"
        case photoRefused = "photo_refused"
        case moderation
        case weeklyBoost = "weekly_boost"
        /// The app's own notification (`NotificationService.notify`).
        case local
        case unknown
    }

    enum Destination: Equatable, Sendable {
        /// A chat, by its match id (lowercased, as `my_matches` gives it).
        case chat(String)
        /// The chat list: a chat push whose chat can't be named.
        case chats
        case likes
        case sessions
        case discover
        case photoRefusal(mediaID: String)
        /// Nowhere new: the screen already shows the account's state (a hold covers everything).
        case current

        /// For the logs.
        var code: String {
            switch self {
            case .chat: "chat"
            case .chats: "chats"
            case .likes: "likes"
            case .sessions: "sessions"
            case .discover: "discover"
            case .photoRefusal: "photo_refusal"
            case .current: "current"
            }
        }

        /// Whether sheets and covers close first, so the destination is what shows. A photo refusal
        /// opens over whatever is on screen; `current` changes nothing.
        var clearsPresentedScreens: Bool {
            switch self {
            case .photoRefusal, .current: false
            default: true
            }
        }
    }

    let kind: Kind
    let destination: Destination

    init(kind: Kind, destination: Destination) {
        self.kind = kind
        self.destination = destination
    }

    init(userInfo info: [AnyHashable: Any]) {
        let chat = Self.chatID(info)
        if let kind = (info["kind"] as? String)?.lowercased() {
            self = Self.named(kind, chat: chat, info: info)
        } else {
            self = Self.unnamed(chat: chat, info: info)
        }
    }

    /// A payload with a `kind` (the backend's own pushes).
    private static func named(_ kind: String, chat: String?, info: [AnyHashable: Any]) -> Self {
        switch kind {
        case "like": Self(kind: .like, destination: .likes)
        case "super_like": Self(kind: .superLike, destination: .likes)
        case "match": Self(kind: .match, destination: chat.map(Destination.chat) ?? .chats)
        case "session_cancelled": Self(kind: .sessionCancelled, destination: chat.map(Destination.chat) ?? .sessions)
        case "session_reminder": Self(kind: .sessionReminder, destination: chat.map(Destination.chat) ?? .sessions)
        case "photo_refused":
            Self(kind: .photoRefused, destination: text(info["media"]).map { .photoRefusal(mediaID: $0) } ?? .current)
        case "moderation": Self(kind: .moderation, destination: .discover)
        case "weekly_boost": Self(kind: .weeklyBoost, destination: .discover)
        // A kind newer than this build: its chat if it names one, its tab if it says it.
        default: Self(kind: .unknown, destination: chat.map(Destination.chat) ?? tab(info) ?? .discover)
        }
    }

    /// A payload without a `kind`: Stream's messages, the app's own, session updates and reactions.
    private static func unnamed(chat: String?, info: [AnyHashable: Any]) -> Self {
        let toChat = chat.map(Destination.chat) ?? .chats
        if info["stream"] is [AnyHashable: Any] { return Self(kind: .message, destination: toChat) }
        if info["chatID"] != nil { return Self(kind: .local, destination: toChat) }
        guard let chat else { return Self(kind: .unknown, destination: tab(info) ?? .discover) }
        return Self(kind: info["session"] != nil ? .sessionUpdate : .reaction, destination: .chat(chat))
    }

    // MARK: Reading the payload

    /// The chat it's about: `chatID` (the app's own), `match` (the backend's and Stream's), or Stream's
    /// `cid` (`messaging:<match>`). Only a UUID is taken: a payload is outside input.
    private static func chatID(_ info: [AnyHashable: Any]) -> String? {
        let stream = info["stream"] as? [AnyHashable: Any]
        let cid = text(stream?["cid"]).flatMap { $0.split(separator: ":", maxSplits: 1).last.map(String.init) }
        for candidate in [text(info["chatID"]), text(info["match"]), cid] {
            if let candidate, let id = UUID(uuidString: candidate) { return id.uuidString.lowercased() }
        }
        return nil
    }

    private static func tab(_ info: [AnyHashable: Any]) -> Destination? {
        switch text(info["tab"])?.lowercased() {
        case "likes": .likes
        case "sessions": .sessions
        case "chats": .chats
        case "discover": .discover
        default: nil
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty
        else { return nil }
        return string
    }
}

/// A tapped notification waiting for the tabs to be on screen: a cold launch (the session and the first
/// reads still coming), a sign-in, a moderation hold. Taken once by MainTabs; a newer tap replaces it.
struct PendingPushRoute: Equatable, Sendable {
    let route: PushRoute
    let tappedAt: Date
    /// The tap came before the app's first screen was up (it launched the app).
    let coldStart: Bool
    let id = UUID()

    /// How long a tap may wait (a sign-in that takes a while) before taking the person somewhere is a
    /// surprise rather than an answer.
    static let lifetime: TimeInterval = 10 * 60

    func isExpired(at now: Date = .now) -> Bool { now.timeIntervalSince(tappedAt) > Self.lifetime }
}
