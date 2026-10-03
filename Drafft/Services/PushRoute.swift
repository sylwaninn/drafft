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
/// - session cancelled: `kind` `session_cancelled`, `match`, `session`; cancelled because its match ended
///   (`session.auto_cancelled`) carries no `match` (no chat any more): opens Sessions.
/// - session reminder: `kind` `session_reminder`, `match`, `session`. Opens the chat; without a usable
///   `match`, Sessions.
/// - reaction (`stream-webhook`): `match` only. Opens the chat.
/// - message (Stream's own push, `scripts/stream-push.ts`): `match`, and `stream` (`type` `message.new`,
///   `cid` `messaging:<match>`). Opens the chat.
/// - photo refused: `kind` `photo_refused`, `media`. Shows why, over the current screen.
/// - moderation (a decision, a hold, a selfie asked for): `kind` `moderation`. Discover: the app shows the
///   account's state on its own (a hold covers everything).
/// - weekly boost: `kind` `weekly_boost`. Opens Discover, where it's used.
/// - the app's own (a message from another chat while the app is open): `chatID`. Opens the chat.
///
/// Anything else (a kind this build doesn't know, or none with nothing else to go on) opens its chat when it
/// names one, its `tab` (`likes`, `sessions`, `chats`, `discover`) when it says one, else Discover.
///
/// A chat push (match, message, the app's own) with no usable chat id (only a UUID is taken) still opens the
/// chat list, but `fallsBack`: `push_opened` counts it `routed` false, as it does an unknown kind that
/// ended on Discover with nothing to name it.
struct PushRoute: Equatable, Sendable {
    /// Event codes shared with the Android app's telemetry (`push_opened`'s and `push_received`'s `kind`):
    /// never renamed. A server kind outside this set is `unknown`.
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
        /// A chat, by its match id: always a lowercased UUID string, as `my_matches` gives it. Only
        /// `PushRoute.init(userInfo:)` builds it, from a validated UUID; a hand-made value must follow it.
        case chat(String)
        /// The chat list: a chat push whose chat can't be named.
        case chats
        case likes
        case sessions
        case discover
        case photoRefusal(mediaID: String)
        /// Nowhere new: the screen already shows the account's state (a hold covers everything).
        case current

        /// A fixed code for the logs (never the chat or media id).
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
    /// The tap shows something, but not what it was about (a chat push with no usable chat id opens the
    /// chat list; an unknown kind with nothing to name opens Discover): `push_opened` is `routed` false.
    let fallsBack: Bool

    /// Internal (not public) for the tests; the app reads a payload with `init(userInfo:)`.
    init(kind: Kind, destination: Destination, fallsBack: Bool = false) {
        self.kind = kind
        self.destination = destination
        self.fallsBack = fallsBack
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
        case "match": toChat(.match, chat)
        case "session_cancelled": Self(kind: .sessionCancelled, destination: chat.map(Destination.chat) ?? .sessions)
        case "session_reminder": Self(kind: .sessionReminder, destination: chat.map(Destination.chat) ?? .sessions)
        case "photo_refused":
            Self(kind: .photoRefused, destination: text(info["media"]).map { .photoRefusal(mediaID: $0) } ?? .current)
        case "moderation": Self(kind: .moderation, destination: .discover)
        case "weekly_boost": Self(kind: .weeklyBoost, destination: .discover)
        default: unrecognised(chat: chat, info: info)
        }
    }

    /// Nothing this build knows: its chat if it names one, its tab if it says one, else Discover (a fallback).
    private static func unrecognised(chat: String?, info: [AnyHashable: Any]) -> Self {
        if let chat { return Self(kind: .unknown, destination: .chat(chat)) }
        if let tab = tab(info) { return Self(kind: .unknown, destination: tab) }
        return Self(kind: .unknown, destination: .discover, fallsBack: true)
    }

    /// A chat push: its chat, or the chat list when no usable id came with it.
    private static func toChat(_ kind: Kind, _ chat: String?) -> Self {
        guard let chat else { return Self(kind: kind, destination: .chats, fallsBack: true) }
        return Self(kind: kind, destination: .chat(chat))
    }

    /// A payload without a `kind`: Stream's messages, the app's own, session updates and reactions.
    private static func unnamed(chat: String?, info: [AnyHashable: Any]) -> Self {
        if info["stream"] is [AnyHashable: Any] { return toChat(.message, chat) }
        if info["chatID"] != nil { return toChat(.local, chat) }
        guard let chat else { return unrecognised(chat: nil, info: info) }
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
    /// The tap came before the tabs were first on screen in this process (it launched the app).
    let coldStart: Bool
    /// The signed-in account (its auth user id) when the tap came; nil when the session wasn't read yet (a
    /// cold launch). Followed only for that same account.
    let account: String?
    let id = UUID()

    /// How long a tap may wait (a sign-in that takes a while) before taking the person somewhere is a
    /// surprise rather than an answer.
    static let lifetime: TimeInterval = 10 * 60

    /// Waited longer than `lifetime`: exactly at it still counts.
    func isExpired(at now: Date = .now) -> Bool { now.timeIntervalSince(tappedAt) > Self.lifetime }
}

/// The one tapped notification waiting for the tabs (`NotificationService` holds it), with the rules of
/// its queue, free of the app so they are unit-tested: a newer tap replaces the waiting one, it's taken
/// once, one that waited too long is dropped, and every tap that is never followed is counted through
/// `skipped` (`push_opened`, `routed` false).
///
/// Taps and accounts: a tap while a person is signed in is bound to that account (followed only for it). A
/// tap before the session is read (the one that launched the app, `account` nil) is bound to whoever the
/// session turns out to be. A tap while signed out in a running app is dropped: the push was for an
/// account that left (its token is unregistered at sign-out), never for the next one to sign in.
struct PushTapQueue {
    private(set) var pending: PendingPushRoute?
    /// The tabs have been on screen once in this process: a tap before that launched the app.
    private var tabsSeen = false
    private let skipped: (PendingPushRoute) -> Void

    init(skipped: @escaping (PendingPushRoute) -> Void) { self.skipped = skipped }

    mutating func tap(_ route: PushRoute, account: String?, now: Date = .now) {
        let tap = PendingPushRoute(route: route, tappedAt: now, coldStart: !tabsSeen, account: account)
        drop()
        if account == nil, tabsSeen {
            skipped(tap)
        } else {
            pending = tap
        }
    }

    /// The tap to follow now, once (the tabs are on screen). One that waited too long is counted and dropped.
    mutating func take(now: Date = .now) -> PendingPushRoute? {
        tabsSeen = true
        defer { pending = nil }
        guard let taken = pending else { return nil }
        guard !taken.isExpired(at: now) else {
            skipped(taken)
            return nil
        }
        return taken
    }

    /// Signed out: a tap meant for the account that left goes nowhere.
    mutating func drop() {
        if let dropped = pending { skipped(dropped) }
        pending = nil
    }
}
