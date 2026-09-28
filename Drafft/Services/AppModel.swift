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
    /// Without drafft tempo: who liked you, blurred by the server (`liked_me` without identities).
    var blurredLikes: [BlurredLike] = [] { didSet { refreshBadges() } }
    /// Current matches (`my_matches`), newest first.
    var matches: [Match] = []

    // Chats
    /// One per active match (`matches`), with its Stream channel (`ChatService`): never sample data.
    var conversations: [Conversation] = [] { didSet { refreshBadges() } }
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
        // The full list with drafft tempo, the blurred one without.
        let liked = isPremium ? likedMe.count : blurredLikes.count
        if liked != likedMeCount { likedMeCount = liked }
    }

    func toggleMute(_ id: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].muted.toggle()
        ChatService.shared.toggleMute(id)
    }

    // MARK: Account (Supabase Auth)

    /// The session ended without the person logging out (revoked, expired, account deleted
    /// elsewhere): back on the welcome screen, a message says so.
    var sessionEndedNotice = false
    /// The person is logging out or deleting their account: the session that ends with it (and any
    /// revocation that races it) is theirs, so no message. Cleared at the next sign-in.
    var leavingOnPurpose = false

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
        Task { await ChatService.shared.markRead(id) }
    }

    /// "Mark as unread": a dot on the chat until it's opened again.
    func markUnread(_ id: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].markedUnread = true
        ChatService.shared.markUnread(id)
    }

    /// Sent at once: the bubble shows before the server has it, the ticks catch up.
    func send(_ content: MessageContent, in id: String, replyTo: String? = nil) {
        guard conversation(id) != nil else { return }
        Haptics.tap()
        ChatService.shared.send(content, in: id, replyTo: replyTo)
    }

    /// Your reaction on one of their messages (never on your own: WhatsApp-style, minus self-reactions).
    func react(_ emoji: String?, to messageID: String, in id: String) {
        guard let message = conversation(id)?.messages.first(where: { $0.id == messageID }), !message.fromMe else { return }
        Haptics.select()
        ChatService.shared.react(emoji, to: messageID, current: message.reaction, in: id)
    }

    func delete(_ messageID: String, in id: String) {
        guard conversation(id)?.messages.first(where: { $0.id == messageID })?.fromMe == true else { return }
        ChatService.shared.delete(messageID, in: id)
    }

    /// A message that couldn't be sent, tapped: sent again.
    func retry(_ messageID: String, in id: String) {
        Haptics.tap()
        ChatService.shared.retry(messageID, in: id)
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
