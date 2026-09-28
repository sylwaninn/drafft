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
    var me = MockData.me
    /// The drafft tempo subscription. Billed and managed by the App Store: the app only reads it
    /// and links to Apple's management sheet. Simulated for now (no StoreKit yet).
    var subscription: TempoSubscription? {
        didSet {
            if subscription == nil { nextWeeklyBoostAt = nil }
            else if oldValue == nil, let s = subscription { nextWeeklyBoostAt = Self.nextWeeklyBoost(after: .now, from: s.started) }
        }
    }
    var isPremium: Bool { subscription != nil }
    /// drafft tempo adds a free boost every week, on the weekday and time it started (the first
    /// one comes with the purchase). With the server, it credits them and pushes; the demo does it here.
    var nextWeeklyBoostAt: Date?

    /// Adds the weekly boosts that came due. Called when the app comes to the front, and at the
    /// due time while it's open.
    func creditWeeklyBoosts() {
        guard isPremium, var next = nextWeeklyBoostAt, next <= .now else { return }
        while next <= .now {
            boosts += 1
            next = next.addingTimeInterval(Self.week)
        }
        nextWeeklyBoostAt = next
    }

    private static let week: TimeInterval = 7 * 24 * 3600

    private static func nextWeeklyBoost(after date: Date, from start: Date) -> Date {
        let weeks = max(0, (date.timeIntervalSince(start) / week).rounded(.down)) + 1
        return start.addingTimeInterval(weeks * week)
    }

    // Likes, super likes & boosts
    /// Free accounts get this many likes a day; Plus is unlimited.
    static let dailyLikes = 20
    static let boostDuration: TimeInterval = 30 * 60
    var likesLeft = 14
    /// Bought in packs (one-time purchases); they never expire.
    var superLikes = 2
    var boosts = 0
    var boostEndsAt: Date?
    /// Confirmation banner after starting a boost (its id restarts the auto-dismiss).
    var boostBanner: UUID?
    /// Sessions the person saved to their calendar (demo: in memory).
    var sessionsInCalendar: Set<UUID> = []

    func isBoosting(at date: Date = .now) -> Bool { (boostEndsAt ?? .distantPast) > date }

    /// 30 minutes at the top of decks nearby.
    func startBoost() {
        guard !profilePaused, boosts > 0, !isBoosting() else { return }
        boosts -= 1
        boostEndsAt = .now.addingTimeInterval(Self.boostDuration)
        Haptics.success()
        boostBanner = UUID()
    }

    enum Consumable { case boost, superLike }

    func add(_ count: Int, of item: Consumable) {
        switch item {
        case .boost: boosts += count
        case .superLike: superLikes += count
        }
    }

    // Account & settings (demo: kept in memory)
    var email = "alex.martin@example.com"
    var language: AppLanguage {
        get { Localization.shared.language }
        set {
            Localization.shared.language = newValue
            NotificationService.shared.language = newValue
        }
    }
    /// Verified at sign-up, can be replaced (after verifying the new one), never removed.
    var phoneNumber: String? = "+33 6 12 34 56 78"
    /// Paused: hidden from everyone, and nothing goes out (no like, pass, message, reaction, boost or
    /// session) until it's resumed. The tabs show a greyed lock over their content (`pausedLock`).
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

    // Discover
    /// Everyone not yet swiped, in order. `deck` is this queue seen through the filters.
    var queue: [Profile] = MockData.deck
    var filters = DiscoverFilters()
    var deck: [Profile] { queue.filter { filters.matches($0, me: me) } }
    var history: [(profile: Profile, liked: Bool)] = []
    /// Icebreaker answers attached to a like; they open the chat if it becomes a match.
    var pendingOpeners: [String: MessageContent] = [:]

    // Chats
    var conversations: [Conversation] = MockData.conversations()
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

    /// Tab badge: muted chats don't count.
    var unreadTotal: Int { conversations.reduce(0) { $0 + ($1.muted ? 0 : $1.unread) } }

    func toggleMute(_ id: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].muted.toggle()
    }

    var upcomingSessions: [(Conversation, SessionProposal)] {
        conversations.flatMap { c in
            c.messages.compactMap { m -> (Conversation, SessionProposal)? in
                if case .session(let s) = m.content, s.status == .pending || s.status == .accepted { return (c, s) }
                return nil
            }
        }
    }

    // MARK: Account (Supabase Auth)

    /// Set when a reset-password link opened the app: the new-password screen shows.
    var choosingNewPassword = false
    /// Set when a link from an auth email couldn't be used: a sheet says why and what to do.
    var authLinkProblem: AuthLinkProblem?

    // MARK: Discover

    var topCard: Profile? { deck.first }

    /// People who already liked you and are still waiting in your deck (Plus shows who).
    var likedMe: [Profile] { queue.filter { $0.interest == .alreadyLikes || $0.superLikedMe } }

    func pass(_ profile: Profile) {
        guard !profilePaused, let i = queue.firstIndex(of: profile) else { return }
        queue.remove(at: i)
        history.append((profile, false))
    }

    /// A super like doesn't use a daily like; it puts you first in their deck with a star, which
    /// in the demo turns someone undecided into a like-back.
    func like(_ profile: Profile, opener: MessageContent? = nil, superLike: Bool = false) {
        guard !profilePaused, let i = queue.firstIndex(of: profile) else { return }
        queue.remove(at: i)
        history.append((profile, true))
        if let opener { pendingOpeners[profile.id] = opener }
        if superLike {
            superLikes = max(0, superLikes - 1)
        } else if !isPremium {
            likesLeft = max(0, likesLeft - 1)
        }

        let interest = superLike && profile.interest == .none ? .likesBackLater : profile.interest
        switch interest {
        case .alreadyLikes:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                self.createMatch(with: profile)
                Haptics.success()
                self.matchScreen = profile
            }
        case .likesBackLater:
            let background = UIApplication.shared.beginBackgroundTask(withName: "match-\(profile.id)")
            Task { @MainActor in
                defer { UIApplication.shared.endBackgroundTask(background) }
                try? await Task.sleep(for: .seconds(5))
                // Undo before the like-back lands cancels it.
                guard self.history.contains(where: { $0.profile.id == profile.id && $0.liked }) else { return }
                self.createMatch(with: profile)
                Haptics.success()
                withAnimation(Motion.bouncy) { self.banner = MatchBanner(profile: profile) }
                // Out of the app: the match comes as a notification instead of the banner.
                if UIApplication.shared.applicationState != .active {
                    await NotificationService.shared.notify(.match, from: profile.firstName, photo: profile.portrait,
                                                            chatID: profile.id, muted: false)
                }
            }
        case .none:
            break
        }
    }

    func undo() {
        guard !profilePaused, let last = history.popLast() else { return }
        pendingOpeners[last.profile.id] = nil
        // A match that already happened stays; the card still comes back for another look.
        queue.insert(last.profile, at: 0)
        Haptics.tap()
    }

    func resetDeck() {
        let hidden = Set(conversations.map(\.id)).union(blocked.map(\.id))
        queue = MockData.deck.filter { !hidden.contains($0.id) }
        history = []
    }

    // MARK: Safety

    /// Mutual like: a conversation appears in Chats, with the icebreaker answer as its first message.
    private func createMatch(with profile: Profile) {
        guard conversation(profile.id) == nil else { return }
        var convo = Conversation(id: profile.id, profile: profile, messages: [], unread: 1, matchedAt: .now)
        // Their super like note opens the chat.
        if let note = profile.superLikeNote {
            convo.messages.append(Message(.text(note), fromMe: false, state: .delivered))
        }
        if let opener = pendingOpeners.removeValue(forKey: profile.id) {
            convo.messages.append(Message(opener, fromMe: true, state: .delivered))
        }
        withAnimation(Motion.snappy) { conversations.insert(convo, at: 0) }
        if case .session(let s) = convo.messages.first?.content {
            simulateReply(in: profile.id, acceptSession: s.id)
        } else if !convo.messages.isEmpty {
            simulateReply(in: profile.id)
        }
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
        guard !profilePaused, let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        let msg = Message(content, fromMe: true, state: .sending, replyTo: replyTo)
        conversations[i].messages.append(msg)
        let convo = conversations.remove(at: i)
        conversations.insert(convo, at: 0)
        Haptics.tap()

        // Photos go through the moderation check, silently: nothing changes for anyone. A flagged
        // one is recorded on the server (media_flags) for actions and metrics.
        if case .photo(_, let data?) = content {
            Task { await ChatMediaCheck.photo(data) }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            self.setState(.sent, for: msg.id, in: id)
            try? await Task.sleep(for: .milliseconds(250))
            self.setState(.delivered, for: msg.id, in: id)
        }
        if case .session(let proposal) = content {
            simulateReply(in: id, acceptSession: proposal.id)
        } else {
            simulateReply(in: id)
        }
    }

    /// Your reaction on one of their messages (never on your own: WhatsApp-style, minus self-reactions).
    func react(_ emoji: String?, to messageID: UUID, in id: String) {
        guard !profilePaused, let c = conversations.firstIndex(where: { $0.id == id }),
              let m = conversations[c].messages.firstIndex(where: { $0.id == messageID }),
              !conversations[c].messages[m].fromMe else { return }
        conversations[c].messages[m].reaction = conversations[c].messages[m].reaction == emoji ? nil : emoji
        Haptics.select()
    }

    func delete(_ messageID: UUID, in id: String) {
        guard let c = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[c].messages.removeAll { $0.id == messageID }
    }

    private func updateSession(_ sessionID: UUID, in id: String, _ change: (inout SessionProposal) -> Void) {
        guard !profilePaused, let c = conversations.firstIndex(where: { $0.id == id }),
              let m = conversations[c].messages.firstIndex(where: {
                  if case .session(let s) = $0.content { return s.id == sessionID }
                  return false
              }),
              case .session(var s) = conversations[c].messages[m].content else { return }
        change(&s)
        withAnimation(Motion.bouncy) { conversations[c].messages[m].content = .session(s) }
    }

    /// Accept one of the proposed times (or the first one), or decline the invite.
    func respond(to sessionID: UUID, in id: String, accept: Bool, pick: Date? = nil) {
        updateSession(sessionID, in: id) { s in
            s.status = accept ? .accepted : .declined
            if accept { s.chosen = pick ?? s.options.first }
        }
        accept ? Haptics.success() : Haptics.tap()
    }

    /// Answer an invite with other times: the old card is marked as countered, a new invite goes out.
    func counter(_ sessionID: UUID, in id: String, with proposal: SessionProposal) {
        updateSession(sessionID, in: id) { $0.status = .countered }
        send(.session(proposal), in: id)
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
    private func simulateReply(in id: String, acceptSession: UUID? = nil) {
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
            if acceptSession == nil, Int.random(in: 0..<2) == 0 { self.partnerReacts(in: id) }
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled, let c2 = self.conversations.firstIndex(where: { $0.id == id }) else { return }
            if let acceptSession, let proposal = self.session(acceptSession, in: id),
               proposal.options.count == 1, !self.hasCountered(in: id) {
                // Demo negotiation: the first single-time invite gets other times suggested back.
                self.updateSession(acceptSession, in: id) { $0.status = .countered }
                var counter = SessionProposal(sport: proposal.sport, options: Self.alternatives(to: proposal.options[0]),
                                              title: proposal.title, note: "", tags: proposal.tags, discovery: proposal.discovery)
                counter.status = .pending
                let incoming = [Message(.text("Can't make that one 😕 Could any of these work?"), fromMe: false),
                                Message(.session(counter), fromMe: false)]
                withAnimation(Motion.snappy) {
                    self.conversations[c2].isTyping = false
                    self.conversations[c2].messages.append(contentsOf: incoming)
                }
                self.received(incoming, in: id)
                return
            }
            var accepted: NotificationText.Kind?
            if let acceptSession, let proposal = self.session(acceptSession, in: id) {
                // They pick the last option you offered.
                self.respond(to: acceptSession, in: id, accept: true, pick: proposal.options.last)
                accepted = .sessionAccepted(proposal.displayTitle)
            }
            let reply = Message(.text(Self.cannedReply(for: self.conversations[c2], accepted: acceptSession != nil)), fromMe: false)
            withAnimation(Motion.snappy) {
                self.conversations[c2].isTyping = false
                self.conversations[c2].messages.append(reply)
            }
            self.received([reply], in: id, as: accepted)
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

    private func session(_ sessionID: UUID, in id: String) -> SessionProposal? {
        conversation(id)?.messages.lazy.compactMap { m -> SessionProposal? in
            if case .session(let s) = m.content, s.id == sessionID { return s }
            return nil
        }.first
    }

    /// Whether the other person already suggested other times in this chat.
    private func hasCountered(in id: String) -> Bool {
        conversation(id)?.messages.contains { m in
            if case .session = m.content { return !m.fromMe }
            return false
        } ?? false
    }

    /// Two nearby alternatives: next day same time, and two days later an hour later.
    private static func alternatives(to date: Date) -> [Date] {
        let cal = Calendar.current
        return [cal.date(byAdding: .day, value: 1, to: date), cal.date(byAdding: .hour, value: 49, to: date)].compactMap { $0 }
    }

    private static func cannedReply(for convo: Conversation, accepted: Bool) -> String {
        if accepted {
            return ["I'm in. I'll be the one stretching dramatically 🙋", "Deal. Don't be late, I warm up without waiting.", "Yes! Adding it to my calendar right now."].randomElement()!
        }
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
    var canLike: Bool { isPremium || likesLeft > 0 }
    var canUndo: Bool { !history.isEmpty }
}
