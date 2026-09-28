import SwiftUI
import UIKit
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case welcome, onboarding, main }
    enum Tab: Hashable { case discover, likes, sessions, chats, me }

    var phase: Phase = .welcome
    /// Changes on sign-out and account deletion: the tabs are rebuilt fresh for the next person
    /// (no chat left open, no sheet, back at the top of every tab).
    var sessionID = 0
    var tab: Tab = .discover
    /// The signed-in person's own profile, as read from the server (never sample data). Empty until
    /// `profileLoad` is `.loaded`: You shows a loading or retry state instead of it until then.
    var me = AppModel.nobody
    enum ProfileLoad: Equatable { case loading, failed, loaded }
    var profileLoad: ProfileLoad = .loading
    /// The signed-in account's last known state on this iPhone (see `LocalCache`, `refreshAccount`).
    @ObservationIgnored var localCache: LocalCache?
    /// The account read in flight, shared by everyone who asks meanwhile.
    @ObservationIgnored var accountRefresh: Task<ProfileSync.Account?, Never>?
    /// The last account read, and when: a read asked for right after it reuses it.
    @ObservationIgnored var lastAccountRead: (at: Date, account: ProfileSync.Account)?
    /// drafft tempo's details as the App Store reports them for this account (plan, price, renewal),
    /// shown in You. Billed and managed by the App Store: the app only reads it and links to
    /// Apple's management sheet. Whether it's on comes from the server: `isPremium`.
    var subscription: TempoSubscription?
    /// The account's wallet on the server (`wallets`, credited by the purchase webhook and the weekly
    /// boost): the only source of drafft tempo, boosts and super likes. Never credited on the device.
    var premiumUntil: Date?
    var isPremium: Bool { (premiumUntil ?? .distantPast) > .now }

    // Likes, super likes & boosts
    /// Free accounts get this many likes in any 24 hours (the server's limit); drafft tempo is unlimited.
    static let dailyLikes = 20
    static let boostDuration: TimeInterval = 30 * 60
    /// Likes left in the last 24 hours, as the server counts them (`likes_left`). Nil until read, and
    /// with drafft tempo.
    var likesLeft: Int?
    /// Bought in packs (one-time purchases); they never expire. From the wallet (`loadWallet`).
    var superLikes = 0
    var boosts = 0
    var boostEndsAt: Date?
    /// Confirmation banner after starting a boost (its id restarts the auto-dismiss).
    var boostBanner: UUID?
    /// A refusal or failure to show above the tabs (a swipe, an undo or a boost that didn't go through).
    var notice: Notice?
    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }
    /// Sessions the person saved to their calendar, in this launch (the lasting link is `SessionCalendar`).
    var sessionsInCalendar: Set<UUID> = []

    func isBoosting(at date: Date = .now) -> Bool { (boostEndsAt ?? .distantPast) > date }

    enum Consumable { case boost, superLike }

    // Account & settings: read from the account at sign-in, emptied at sign-out.
    var email = ""
    var language: AppLanguage {
        get { Localization.shared.language }
        set {
            Localization.shared.language = newValue
            NotificationService.shared.language = newValue
        }
    }
    /// Verified at sign-up, can be replaced (after verifying the new one), never removed. Read from
    /// the account (Supabase Auth keeps the verified number), nil until then.
    var phoneNumber: String?
    /// Paused: hidden from everyone, and discovery waits (no like, pass, undo or boost) until it's
    /// resumed; Discover shows a lock over the deck (`pausedLock`). Chats, sessions, reports and the
    /// profile keep working with current matches.
    var profilePaused = false { didSet { pauseChanged(from: oldValue) } }
    /// Set while applying the server's own state, so it isn't sent back.
    @ObservationIgnored var pauseFromServer = false

    var notifyMatches = true
    var notifyMessages = true
    var notifySessions = true
    /// People you blocked: gone from Discover, Likes and Chats until you unblock them.
    var blocked: [Profile] = []
    var blockedCount: Int { blocked.count }
    /// Data export: requested here, sent by email as a download link (server side).
    var dataExportRequestedAt: Date?

    /// 0…1, with the next thing worth adding.
    var profileCompletion: (value: Double, next: String?) {
        let checks: [(Bool, String)] = [
            (me.allPhotos.count >= 4, L("Add a few more photos")),
            (!me.bio.isEmpty, L("Write a short bio")),
            (me.voiceIntro != nil, L("Record a voice intro")),
            (me.prompts.count >= 3, L("Answer a third prompt")),
            (!me.goal.isEmpty, L("Add what you're training for"))
        ]
        let done = checks.filter(\.0).count
        return (Double(done) / Double(checks.count), checks.first { !$0.0 }?.1)
    }

    // Discover (AppModel+Discover): batches from `discover`, kept on this iPhone between launches.
    /// The cards not swiped yet, best first. Only the server's: never sample people.
    var queue: [Profile] = []
    var deck: [Profile] { queue }
    /// Where the deck stands (first load, a refusal like `location_required`).
    var deckState: DeckState = .idle
    enum DeckState: Equatable { case idle, loading, loaded, failed(String) }
    var filters = DiscoverFilters() { didSet { if filters != oldValue { filtersChanged() } } }
    /// This session's swipes, last one last: what undo can bring back (the server undoes the last one,
    /// within 10 minutes, if it didn't make a match).
    var history: [Swiped] = []
    struct Swiped {
        let profile: Profile
        let liked: Bool
        let superLike: Bool
        let at: Date
        /// Answered from Likes (it goes back there on undo).
        var fromLikes = false
        var matched = false
    }
    @ObservationIgnored var discovery = DiscoveryState()

    // Likes and matches (AppModel+Matches)
    /// Everyone who liked you and is waiting for an answer (`liked_me`), super likes first.
    var likedMe: [Profile] = [] { didSet { refreshBadges() } }
    /// Current matches (`my_matches`), newest first.
    var matches: [Match] = []

    // Chats
    var conversations: [Conversation] = MockData.conversations() { didSet { refreshBadges() } }
    /// The chat currently on screen (its messages count as read).
    var openChatID: String?
    /// A request to show a chat from the Chats tab (match screen, banner); consumed by ConversationsView.
    var chatRequest: String?
    /// Bumped each time a chat is opened from outside it (notification, match banner): the chat
    /// jumps to its latest message even if it was already open and scrolled up.
    var latestRequest: LatestRequest?
    struct LatestRequest: Equatable {
        let chatID: String
        let token = UUID()
    }

    // Match moments
    var matchScreen: Profile?
    var banner: MatchBanner?

    struct MatchBanner: Identifiable, Equatable {
        let id = UUID()
        let profile: Profile
    }

    /// Tab badge: muted chats don't count. Stored, and only written when it changes, like
    /// `likedMeCount`: the tab bar reads these, so a new message or a typing dot doesn't re-render it.
    private(set) var unreadTotal = 0
    /// Tab badge: people who like you, from the deck (`likedMe`).
    private(set) var likedMeCount = 0

    init() { refreshBadges() }

    private func refreshBadges() {
        let unread = conversations.reduce(0) { $0 + ($1.muted ? 0 : $1.unread) }
        if unread != unreadTotal { unreadTotal = unread }
        let liked = likedMe.count
        if liked != likedMeCount { likedMeCount = liked }
    }

    func toggleMute(_ id: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].muted.toggle()
    }

    // MARK: Account (Supabase Auth)

    /// The session ended without the person logging out (revoked, expired, account deleted
    /// elsewhere): back on the welcome screen, a message says so.
    var sessionEndedNotice = false

    // MARK: Discover

    var topCard: Profile? { deck.first }

    /// The chat with this person (match screen, banner), by their profile id: a chat's id is its match's.
    func openChat(person id: String) {
        openChat(conversations.first { $0.profile.id == id }?.id ?? id)
    }

    func openChat(_ id: String) {
        matchScreen = nil
        banner = nil
        tab = .chats
        chatRequest = id
        latestRequest = LatestRequest(chatID: id)
    }

    // MARK: Chat

    func conversation(_ id: String) -> Conversation? { conversations.first { $0.id == id } }

    func markRead(_ id: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].unread = 0
        conversations[i].markedUnread = false
    }

    /// "Mark as unread": a dot on the chat until it's opened again.
    func markUnread(_ id: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].markedUnread = true
    }

    /// Optimistic send: the bubble appears immediately, delivery ticks catch up.
    func send(_ content: MessageContent, in id: String, replyTo: UUID? = nil) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        let msg = Message(content, fromMe: true, state: .sending, replyTo: replyTo)
        conversations[i].messages.append(msg)
        let convo = conversations.remove(at: i)
        conversations.insert(convo, at: 0)
        Haptics.tap()

        // Photos go through the moderation check, silently: nothing changes for anyone. A flagged
        // one is recorded on the server (media_flags) for actions and metrics. A sample person never
        // receives it: nothing is uploaded or checked.
        if case .photo(_, let data?) = content, !MockData.isSample(id) {
            Task { await ChatMediaCheck.photo(data) }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            self.setState(.sent, for: msg.id, in: id)
            try? await Task.sleep(for: .milliseconds(250))
            self.setState(.delivered, for: msg.id, in: id)
        }
        // Only sample people answer on their own; a real match's chat is the chat service's.
        guard MockData.isSample(id) else { return }
        // Sessions are real (`SessionStore`): nobody simulated answers them.
        if case .session = content { return }
        simulateReply(in: id)
    }

    /// Your reaction on one of their messages (never on your own: WhatsApp-style, minus self-reactions).
    func react(_ emoji: String?, to messageID: UUID, in id: String) {
        guard let c = conversations.firstIndex(where: { $0.id == id }),
              let m = conversations[c].messages.firstIndex(where: { $0.id == messageID }),
              !conversations[c].messages[m].fromMe else { return }
        conversations[c].messages[m].reaction = conversations[c].messages[m].reaction == emoji ? nil : emoji
        Haptics.select()
    }

    func delete(_ messageID: UUID, in id: String) {
        guard let c = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[c].messages.removeAll { $0.id == messageID }
    }

    private func setState(_ state: DeliveryState, for messageID: UUID, in id: String) {
        guard let c = conversations.firstIndex(where: { $0.id == id }),
              let m = conversations[c].messages.firstIndex(where: { $0.id == messageID }) else { return }
        if conversations[c].messages[m].state < state {
            withAnimation(Motion.snappy) { conversations[c].messages[m].state = state }
        }
    }

    private var replyTasks: [String: Task<Void, Never>] = [:]

    /// Simulated partner: reads, types, replies. Debounced so a burst of sends gets one answer.
    private func simulateReply(in id: String) {
        replyTasks[id]?.cancel()
        // A few seconds of background time: leaving the app right after sending still gets the reply
        // (and its notification).
        let background = UIApplication.shared.beginBackgroundTask(withName: "reply-\(id)")
        replyTasks[id] = Task { @MainActor in
            defer { UIApplication.shared.endBackgroundTask(background) }
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled, let c = self.conversations.firstIndex(where: { $0.id == id }) else { return }
            withAnimation(Motion.snappy) {
                for m in self.conversations[c].messages.indices where self.conversations[c].messages[m].fromMe {
                    self.conversations[c].messages[m].state = .read
                }
                self.conversations[c].isTyping = true
            }
            // Demo: now and then they react to your last message before answering.
            if Int.random(in: 0..<2) == 0 { self.partnerReacts(in: id) }
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled, let c2 = self.conversations.firstIndex(where: { $0.id == id }) else { return }
            let reply = Message(.text(Self.cannedReply(for: self.conversations[c2])), fromMe: false)
            withAnimation(Motion.snappy) {
                self.conversations[c2].isTyping = false
                self.conversations[c2].messages.append(reply)
            }
            self.received([reply], in: id)
        }
    }

    /// The other person reacts to your last text message (demo), with a notification when the chat
    /// isn't on screen: "Maya reacted ❤️ to: “…”".
    private func partnerReacts(in id: String) {
        guard let c = conversations.firstIndex(where: { $0.id == id }),
              let m = conversations[c].messages.lastIndex(where: {
                  if case .text = $0.content { return $0.fromMe && $0.reaction == nil }
                  return false
              }),
              case .text(let text) = conversations[c].messages[m].content else { return }
        let emoji = ["❤️", "😂", "🔥", "👏"].randomElement()!
        withAnimation(Motion.bouncy) { conversations[c].messages[m].reaction = emoji }
        guard !(openChatID == id && UIApplication.shared.applicationState == .active) else { return }
        let profile = conversations[c].profile
        let muted = conversations[c].muted
        Task {
            await NotificationService.shared.notify(.reaction(emoji, text), from: profile.firstName,
                                                    photo: profile.portrait, chatID: id, muted: muted)
        }
    }

    /// Messages that just arrived in a chat. Unless that chat is on screen right now: unread count,
    /// and a notification (NotificationService applies the Messages settings and the chat's mute).
    private func received(_ messages: [Message], in id: String, as kind: NotificationText.Kind? = nil) {
        guard let c = conversations.firstIndex(where: { $0.id == id }), let last = messages.last else { return }
        let onScreen = openChatID == id && UIApplication.shared.applicationState == .active
        if onScreen {
            Haptics.tap()
            return
        }
        conversations[c].unread += messages.count
        let resolved: NotificationText.Kind = if let kind { kind }
            else if case .session(let s) = last.content { .sessionProposed(s.displayTitle) }
            else { .message }
        let profile = conversations[c].profile
        let muted = conversations[c].muted
        Task {
            await NotificationService.shared.notify(resolved, from: profile.firstName, photo: profile.portrait,
                                                    chatID: id, muted: muted, preview: last.previewText)
        }
    }

    private static func cannedReply(for convo: Conversation) -> String {
        let pool = [
            "Ha, love that.",
            "Okay, you have my attention.",
            "Wait, send more of that 😂",
            "Same page. When are you free this week?",
            "That's exactly my kind of plan."
        ]
        return pool[convo.messages.count % pool.count]
    }
}

extension Array where Element: Identifiable {
    func uniqued() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}

/// What the App Store says about the subscription: the plan, when it started, the end of the
/// current period, and whether it renews (turned off when cancelled in the App Store).
struct TempoSubscription: Equatable {
    let plan: PaywallView.Plan
    let started: Date
    var periodEnds: Date
    var willRenew = true
    /// How the price reads ("€12.99 a month"), from the App Store product.
    var billing: String

    init(plan: PaywallView.Plan, started: Date = .now, billing: String) {
        self.plan = plan
        self.started = started
        self.billing = billing
        periodEnds = Calendar.current.date(byAdding: .month, value: plan.months, to: started) ?? started
    }
}

extension AppModel {
    /// Unknown counts as yes: the server has the last word (`daily_like_limit`).
    var canLike: Bool { isPremium || (likesLeft ?? 1) > 0 }
    /// The last swipe, within 10 minutes, if it didn't make a match: the server's rule.
    var canUndo: Bool {
        guard let last = history.last else { return false }
        return !last.matched && last.at.timeIntervalSinceNow > -Self.undoWindow
    }
    static let undoWindow: TimeInterval = 10 * 60
}
