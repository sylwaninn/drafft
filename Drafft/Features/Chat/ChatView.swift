import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

/// Opening a chat on a given session card (from the Sessions tab).
struct ChatRoute: Hashable {
    let chatID: String
    var sessionID: UUID?
}

struct ChatView: View {
    let conversationID: String
    /// Scroll to this session's card and flash it (from the Sessions tab).
    var focusSession: UUID?
    @State private var highlighted: String?
    @Environment(AppModel.self) private var app
    @State private var draft = ""
    @State private var viewer: MediaItem?
    @State private var showProfile = false
    @State private var proposing = false
    @State private var replyingTo: Message?
    @State private var focused: FocusedMessage?
    @State private var counterTo: SessionProposal?
    /// Where the thread sits: pinned to the latest message until the person scrolls up, then
    /// kept exactly where they left it (back from the background, a photo, a sheet).
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var scroll = ScrollMemo()
    /// Scrolled away from the end: the jump-to-latest button shows. Written only when it flips.
    @State private var awayFromEnd = false
    /// Their messages that arrived while scrolled up: the count on the jump button.
    @State private var unseen = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSafety = false
    @State private var safetyFor: SafetyRequest?

    struct SafetyRequest: Identifiable {
        let id = UUID()
        let session: SessionProposal
        let date: Date
    }
    @Environment(\.dismiss) private var dismissChat

    private var convo: Conversation? { app.conversation(conversationID) }

    var body: some View {
        Group {
            if let convo {
                content(convo)
            } else {
                ContentUnavailableView("Chat not found", image: "chat-round")
            }
        }
        .onAppear {
            app.openChatID = conversationID
            ChatService.shared.open(conversationID)
            app.markRead(conversationID)
        }
        .onDisappear {
            if app.openChatID == conversationID { app.openChatID = nil }
            ChatService.shared.close(conversationID)
            AudioPlayback.shared.stop()
        }
        // Typing: shown to the other person while there's a draft (stops when it's sent or cleared).
        .onChange(of: draft) { _, text in ChatService.shared.typing(in: conversationID, text: text) }
    }

    /// Back to the list, where the chat shows as unread again (set after leaving, or the chat
    /// being open would clear it straight away).
    private func markUnread() {
        Haptics.tap()
        dismissChat()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            app.markUnread(conversationID)
        }
    }

    /// Back to the chat list first, then the block lands (the chat disappears from it).
    private func blockFromChat(_ person: Profile) {
        Haptics.success()
        dismissChat()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            app.block(person)
        }
    }

    private func dismissFocus() {
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) { focused = nil }
    }

    private func content(_ convo: Conversation) -> some View {
        ScrollViewReader { reader in
        ScrollView {
            // Plain VStack: a lazy stack estimated the height of messages not yet laid out, so
            // scrolling up through older ones made the list jump.
            VStack(spacing: DS.Space.xs) {
                ChatHeaderCard(convo: convo) { showProfile = true }
                    .padding(.top, DS.Space.sm)
                    .padding(.bottom, DS.Space.lg)

                ForEach(Array(convo.messages.enumerated()), id: \.element.id) { i, m in
                    let prev = i > 0 ? convo.messages[i - 1] : nil
                    let next = i + 1 < convo.messages.count ? convo.messages[i + 1] : nil
                    if prev == nil || !Calendar.current.isDate(prev!.date, inSameDayAs: m.date) || m.date.timeIntervalSince(prev!.date) > 3600 {
                        // A separator chip, never loose text on the page.
                        Text(m.date.dayStamp)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.Palette.body)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, DS.Space.md)
                            .padding(.vertical, 6)
                            .background(DS.Palette.white, in: .capsule)
                            .padding(.vertical, DS.Space.sm)
                    }
                    MessageRow(
                        message: m,
                        convo: convo,
                        groupedWithNext: next?.fromMe == m.fromMe && (next.map { $0.date.timeIntervalSince(m.date) < 300 } ?? false),
                        onOpen: { viewer = $0 },
                        onCounterSession: { counterTo = $0 },
                        onSessionSafety: { s, d in
                            // After the card has settled into "Confirmed".
                            Task {
                                try? await Task.sleep(for: .milliseconds(250))
                                safetyFor = SafetyRequest(session: s, date: d)
                            }
                        },
                        onReply: { m in withAnimation(Motion.snappy) { replyingTo = m } },
                        onRetry: { m in app.retry(m.id, in: conversationID) },
                        onFocus: { m, frame in
                            var t = Transaction(animation: nil)
                            t.disablesAnimations = true
                            withTransaction(t) { focused = FocusedMessage(message: m, frame: frame) }
                        },
                        hidden: focused?.id == m.id,
                        highlighted: highlighted == m.id
                    )
                    .id(m.id)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85, anchor: m.fromMe ? .bottomTrailing : .bottomLeading).combined(with: .opacity),
                        removal: .opacity))
                }

                if convo.isTyping {
                    HStack {
                        TypingDots()
                            .padding(.horizontal, DS.Space.lg)
                            .frame(height: 40)
                            .background(DS.Palette.white, in: .rect(cornerRadius: 20))
                        Spacer()
                    }
                    .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
                    .id("typing")
                }
                // The end of the thread: where a chat always opens.
                Color.clear.frame(height: 1).id(Self.bottomID)
            }
            .scrollTargetLayout()
            .padding(.horizontal, DS.Space.md)
            .padding(.bottom, DS.Space.sm)
            .animation(Motion.snappy, value: convo.messages.count)
            .animation(Motion.snappy, value: convo.isTyping)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        // Keyboard, composer, reply quote: the visible bottom stays put above them, so whatever was
        // on screen is pushed up, never covered and never scrolled away (WhatsApp).
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .onScrollGeometryChange(for: ScrollMetrics.self) { g in
            ScrollMetrics(offset: g.contentOffset.y,
                          maxOffset: g.contentSize.height + g.contentInsets.bottom - g.containerSize.height,
                          content: g.contentSize.height,
                          container: g.containerSize.height,
                          // The keyboard and the composer don't shrink the scroll view: they grow
                          // its bottom inset. Watching only the size missed them.
                          bottomInset: g.contentInsets.bottom)
        } action: { old, new in
            scroll.offset = new.offset
            scroll.atBottom = new.offset >= new.maxOffset - 24
            let viewportChanged = new.container != old.container || new.bottomInset != old.bottomInset
            // Pinned to the end: follow it (new message, typing, keyboard, heights settling on
            // open). Scrolled up: nothing moves here; the size-change anchor keeps the view.
            if scroll.stick && (new.content != old.content || viewportChanged) {
                pinToBottom(animated: scroll.settled)
            }
            // The ↓ button: only once clearly away from the end (a bit more than a message's
            // height), never at the end itself or on the first pixels of a scroll.
            let away = new.maxOffset - new.offset > Self.jumpButtonDistance
            if awayFromEnd != away { awayFromEnd = away }
            if scroll.atBottom && unseen > 0 { unseen = 0 }
        }
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.6) { ids in
            // The lowest message on screen: the anchor that brings the person back to this exact
            // place after the background, whatever the keyboard did meanwhile.
            let index = Dictionary(uniqueKeysWithValues: convo.messages.enumerated().map { ($1.id, $0) })
            scroll.lastVisible = ids.max { (index[$0] ?? -1) < (index[$1] ?? -1) }
        }
        .onScrollPhaseChange { old, new in
            scroll.touching = new == .interacting
            if new == .interacting { scroll.stick = false }
            if new == .idle && old != .idle { scroll.stick = scroll.atBottom }
        }
        // Their new message: followed if you're at the end, otherwise counted on the jump button
        // and the thread stays where you're reading. Typing only shows if you're at the end.
        .onChange(of: convo.messages.last?.id) { _, _ in
            guard let last = convo.messages.last, !last.fromMe else { return }
            if scroll.stick && !scroll.touching {
                pinToBottom(animated: scroll.settled)
            } else {
                unseen += 1
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if awayFromEnd {
                JumpToLatestButton(unseen: unseen) {
                    scroll.stick = true
                    unseen = 0
                    pinToBottom(animated: true)
                }
                .padding(.trailing, DS.Space.md)
                .padding(.bottom, DS.Space.sm)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(Motion.snappy, value: awayFromEnd)
        // Opened from a notification or a banner: straight to the newest message, even if this
        // chat was already open and scrolled up (and before the background restore puts it back).
        .onChange(of: app.latestRequest) { _, request in
            guard request?.chatID == conversationID else { return }
            scroll.saved = nil
            scroll.stick = true
            pinToBottom(animated: false)
        }
        .onChange(of: scenePhase) { old, new in
            if old == .active && new != .active {
                if scroll.saved == nil { scroll.saved = scroll.stick ? nil : scroll.lastVisible }
                scroll.away = true
            } else if new == .active && scroll.away {
                scroll.away = false
                // Replies that came in while away were read on arrival: this chat is on screen.
                app.markRead(conversationID)
                Task { await restoreScroll() }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.canvasSoft)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .topBar { chatBar(convo) }
        .bottomBar {
            Composer(text: $draft, onSend: { content in
                scroll.stick = true // your own message always brings you to the end
                app.send(content, in: conversationID, replyTo: replyingTo?.id)
                withAnimation(Motion.snappy) { replyingTo = nil }
            }, reply: replyingTo.map { m in
                (m.id, m.fromMe ? "yourself" : convo.profile.name, m.previewText)
            }, onCancelReply: {
                withAnimation(Motion.snappy) { replyingTo = nil }
            })
        }
        // The tab bar is hidden by the stack that pushes the chat (see ConversationsView), so it
        // comes back the moment Back starts.
        .sheet(isPresented: $showProfile) {
            Group {
                NavigationStack {
                    ProfileDetailView(profile: convo.profile, mode: .sheet, onBlocked: { dismissChat() })
                }
            }
            .sheetSurface()
        }
        .sheet(item: $counterTo) { original in
            Group {
                ProposeSessionSheet(profile: convo.profile, me: app.publicMe, sendTitle: L("Send new times"), counterTo: original) { p in
                    app.counterSession(original.id, in: conversationID, with: p)
                }
            }
            .sheetSurface()
        }
        .sheet(isPresented: $proposing) {
            Group {
                ProposeSessionSheet(profile: convo.profile, me: app.publicMe) { p in
                    app.proposeSession(p, in: conversationID)
                }
            }
            .sheetSurface()
        }
        .fullScreenCover(item: $viewer) { MediaViewer(items: MediaItem.gallery(of: convo), start: $0) }
        .sheet(item: $safetyFor) { r in Group { SessionSafetySheet(session: r.session, date: r.date, partner: convo.profile.name) }.sheetSurface() }
        .sheet(isPresented: $showSafety) {
            ReportSheet(profile: convo.profile) { blockFromChat(convo.profile) }
                .sheetSurface()
        }
        // Clear cover, no system slide: the overlay fades itself over the nav bar and composer.
        .fullScreenCover(item: $focused) { f in
            MessageFocusOverlay(focus: f, convo: convo, onReact: { e in
                app.react(e, to: f.message.id, in: convo.id)
                dismissFocus()
            }, onReply: {
                withAnimation(Motion.snappy) { replyingTo = f.message }
            }, onDismiss: dismissFocus)
            .presentationBackground(.clear)
        }
        .task(id: focusSession) { await reveal(convo, with: reader) }
        }
    }

    /// The overflow menu: vertical dots, neutral. Profile and sessions are one tap away in the bar:
    /// this is about the chat, then safety, apart.
    private func moreMenu(_ convo: Conversation) -> some View {
        Menu {
            Section {
                Button(convo.muted ? "Unmute notifications" : "Mute notifications",
                       image: .icon(convo.muted ? "bell" : "bell-off")) {
                    app.toggleMute(conversationID)
                }
                Button("Mark as unread", image: .icon("letter-unread")) { markUnread() }
            }
            Section {
                Button("Report or block", image: .icon("shield-warning"), role: .destructive) { showSafety = true }
            }
        } label: {
            // A drawn image, never a titled Label: no text can show, VoiceOver reads the label below.
            Image("menu-dots-vertical")
                .font(.body.weight(.semibold))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 40, height: 40)
                .glassEffect(.regular, in: .circle)
                .frame(width: Self.barControl, height: Self.barControl)
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        // Neutral icon: the menu doesn't take the accent tint.
        .tint(DS.Palette.ink)
        .accessibilityLabel("More")
    }

    /// "Typing…" or "Active now" for VoiceOver on the header (the thread shows the typing dots).
    private func presence(_ convo: Conversation) -> Text {
        if convo.isTyping { return Text("Typing…") }
        return convo.online ? Text("Active now") : Text(verbatim: "")
    }

    /// Header controls are 44 pt discs, as iOS 26 draws Back.
    static let barControl: CGFloat = 44

    /// The chat's own header, plain views pinned by `topBar` (the system bar is hidden): native bar
    /// items didn't render custom icons reliably on device. Back, their avatar and first name (the
    /// name takes the room left and truncates only if it can't fit), then the two actions.
    private func chatBar(_ convo: Conversation) -> some View {
        HStack(spacing: DS.Space.sm) {
            Button {
                Haptics.tap()
                dismissChat()
            } label: {
                Image("alt-arrow-left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular, in: .circle)
                    .frame(width: Self.barControl, height: Self.barControl)
                    .contentShape(.circle)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Back")

            // WhatsApp's header: their avatar right after Back, the first name beside it. Tapping
            // either opens their profile.
            Button { showProfile = true } label: {
                ChatTitle(convo: convo)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(convo.profile.name)'s profile")
            .accessibilityValue(presence(convo))

            // Proposing a session is the chat's main action: a solid accent disc.
            Button {
                Haptics.tap()
                proposing = true
            } label: {
                Image("calendar-add")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.onLime)
                    .frame(width: Self.barControl, height: Self.barControl)
                    .background(DS.Palette.lime, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Propose a session")

            moreMenu(convo)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.xs)
        .padding(.bottom, DS.Space.sm)
    }

    private static let bottomID = "chat-bottom"
    /// How far from the end, in points, before the jump-to-latest button shows.
    private static let jumpButtonDistance: CGFloat = 240

    private func pinToBottom(animated: Bool) {
        if animated {
            withAnimation(Motion.snappy) { position.scrollTo(edge: .bottom) }
        } else {
            var t = Transaction(animation: nil)
            t.disablesAnimations = true
            withTransaction(t) { position.scrollTo(edge: .bottom) }
        }
    }

    /// Back from the background: exactly where the person was, anchored on the lowest message they
    /// could see (not a pixel offset: the keyboard may have closed meanwhile). Twice, so a relayout
    /// on the way back (keyboard, traits) can't win.
    private func restoreScroll() async {
        for _ in 0..<2 {
            if scroll.stick {
                pinToBottom(animated: false)
            } else if let id = scroll.saved {
                var t = Transaction(animation: nil)
                t.disablesAnimations = true
                withTransaction(t) { position.scrollTo(id: id, anchor: .bottom) }
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        scroll.saved = nil
    }

    /// Opens on the latest message, or (from Sessions) centres the session card we came for,
    /// then flashes it once. Only on arrival: coming back from a photo or a cover keeps the place.
    private func reveal(_ convo: Conversation, with reader: ScrollViewProxy) async {
        let key = focusSession?.uuidString ?? "bottom"
        guard scroll.revealed != key else { return }
        scroll.revealed = key
        // Normal entry: pinned to the latest message; heights settling (images, composer) keep
        // it pinned without animation until the thread has settled.
        guard focusSession != nil else {
            scroll.stick = true
            pinToBottom(animated: false)
            try? await Task.sleep(for: .milliseconds(600))
            // Once more after images, the composer and the push transition have settled.
            if scroll.stick { pinToBottom(animated: false) }
            scroll.settled = true
            return
        }
        scroll.stick = false
        scroll.settled = true
        guard let focusSession,
              let message = convo.messages.first(where: {
                  if case .session(let s) = $0.content { return s.id == focusSession }
                  return false
              }) else { return }
        try? await Task.sleep(for: .milliseconds(80)) // let the list lay out first
        reader.scrollTo(message.id, anchor: .center)
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(Motion.snappy) { highlighted = message.id }
        try? await Task.sleep(for: .seconds(1.4))
        withAnimation(.easeOut(duration: 0.5)) { highlighted = nil }
    }
}

/// Scroll bookkeeping for a chat. A plain reference, not observed: it changes on every scroll
/// frame and must never re-render the thread.
private final class ScrollMemo {
    var offset: CGFloat = 0
    var atBottom = true
    /// Follow the end of the thread (true on open, false once the person scrolls up).
    var stick = true
    /// The initial layout has settled: later pins animate.
    var settled = false
    /// The lowest message on screen, kept while the app is away from the foreground.
    var saved: String?
    /// Lowest message currently on screen.
    var lastVisible: String?
    /// Left the foreground (inactive or background) and not back yet.
    var away = false
    /// A finger is on the thread.
    var touching = false
    /// What was last revealed on arrival ("bottom" or a session ID).
    var revealed: String?
}

private struct ScrollMetrics: Equatable {
    var offset: CGFloat
    var maxOffset: CGFloat
    var content: CGFloat
    var container: CGFloat
    var bottomInset: CGFloat
}

/// WhatsApp's arrow: back to the newest message, with how many of theirs arrived meanwhile.
private struct JumpToLatestButton: View {
    let unseen: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("alt-arrow-down")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
                .contentShape(.circle)
                .overlay(alignment: .topTrailing) {
                    if unseen > 0 {
                        Text("\(unseen)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(DS.Palette.onLime)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(DS.Palette.lime, in: .capsule)
                            .offset(x: 4, y: -4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(Motion.bouncy, value: unseen)
        .accessibilityLabel(unseen > 0 ? "\(unseen) new messages, go to the latest" : "Go to the latest message")
    }
}

// MARK: - Header

/// The bar's title, WhatsApp style: their avatar (Back's size) and the first name beside it, with
/// "Typing…" or "Active now" under the name. The name is the one header text that may end with
/// "…": it takes the room up to the trailing buttons, never more (DESIGN.md, Headers).
private struct ChatTitle: View {
    let convo: Conversation

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Avatar(name: convo.profile.portrait, size: ChatView.barControl)
            VStack(alignment: .leading, spacing: 0) {
                // No capsule behind: the bar's own blur is the only backdrop, so the text uses the
                // page's inks (ink, then body at 4.5:1 on sage), not system greys.
                Text(convo.profile.name)
                    .font(.headline)
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(1)
                    // design-lint: allow truncation - the chat header name, asked for by the user (DESIGN.md, Headers)
                    .truncationMode(.tail)
                PresenceLine(convo: convo)
            }
        }
    }
}

/// Under the name in the bar: "Typing…", or "Active now" while they have the app open (nothing otherwise).
private struct PresenceLine: View {
    let convo: Conversation

    var body: some View {
        if convo.isTyping || convo.online {
            Text(convo.isTyping ? "Typing…" : "Active now")
                .font(.caption.weight(.semibold))
                .foregroundStyle(convo.isTyping ? DS.Palette.accentInk : DS.Palette.body)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
    }
}

struct ChatHeaderCard: View {
    let convo: Conversation
    let onTap: () -> Void

    var body: some View {
        card
            // At the top of what's loaded: the page before (the thread keeps its place, the size-change
            // anchor holds the bottom).
            .onAppear { ChatService.shared.loadOlder(convo.id) }
    }

    private var card: some View {
        Button(action: onTap) {
            VStack(spacing: DS.Space.md) {
                Avatar(name: convo.profile.portrait, size: 88, ring: true)
                VStack(spacing: 4) {
                    // Names wrap, never truncate.
                    Text("You matched with \(convo.profile.name)")
                        .font(.headline)
                        .foregroundStyle(DS.Palette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(convo.matchedAt.formatted(.relative(presentation: .named).locale(.app)).capitalizedFirst)
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.body)
                        .lineLimit(1)
                }
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity)
            // A white block, like every other section: nothing loose on the sage page.
            .background(DS.Palette.white, in: .rect(cornerRadius: DS.Radius.xl))
            .contentShape(.rect(cornerRadius: DS.Radius.xl))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens their profile")
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension Date {
    var dayStamp: String {
        let cal = Calendar.current
        let time = formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app))
        if cal.isDateInToday(self) { return L("Today \(time)") }
        if cal.isDateInYesterday(self) { return L("Yesterday \(time)") }
        return "\(formatted(.dateTime.weekday(.wide).locale(.app))) \(time)"
    }
}

// MARK: - Message row

struct MessageRow: View {
    let message: Message
    let convo: Conversation
    let groupedWithNext: Bool
    let onOpen: (MediaItem) -> Void
    /// Opens the "other times" sheet for an invite.
    var onCounterSession: (SessionProposal) -> Void = { _ in }
    /// A session time was confirmed (by you) or the safety tips were asked for from its card.
    var onSessionSafety: (SessionProposal, Date) -> Void = { _, _ in }
    var onReply: (Message) -> Void = { _ in }
    /// A message that couldn't be sent, tapped.
    var onRetry: (Message) -> Void = { _ in }
    /// Long press: lift this bubble into the reactions overlay.
    var onFocus: (Message, CGRect) -> Void = { _, _ in }
    /// Hidden in the list while its copy is lifted in the overlay.
    var hidden = false
    /// Render only the bubble (the overlay's copy): no swipe, no long press.
    var presentation = false
    /// The card we came for (from Sessions): a lime ring around the bubble itself, fading out.
    var highlighted = false
    /// Where the bubble sits on screen, for the long-press lift. A plain reference, not state:
    /// it changes on every frame of a scroll or a push, and as state it re-rendered every row of
    /// the chat each frame (the chat stayed unresponsive for a second or two on arrival).
    @State private var frameBox = FrameBox()
    private final class FrameBox { var rect: CGRect = .zero }
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    /// Swipe right to reply, like WhatsApp: the bubble follows, an arrow fills in, release past it.
    @State private var swipe: CGFloat = 0
    private let replyThreshold: CGFloat = 56

    private var mine: Bool { message.fromMe }

    var body: some View {
        if presentation {
            bubbleWithReaction
        } else {
            row
        }
    }

    private var bubbleWithReaction: some View {
        bubble
            .overlay(alignment: mine ? .bottomLeading : .bottomTrailing) {
                if let r = message.reaction {
                    Text(r)
                        .font(.system(size: 14))
                        .padding(5)
                        .background(DS.Palette.white, in: .circle)
                        .overlay(Circle().strokeBorder(DS.Palette.canvasSoft, lineWidth: 2))
                        .offset(x: mine ? -10 : 10, y: 14)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Reaction \(r)")
                }
            }
    }

    private var row: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if let q = quoted, !isText { quote(q) }
            HStack(alignment: .bottom, spacing: DS.Space.sm) {
                if mine { Spacer(minLength: 56) }
                bubbleWithReaction
                    .background {
                        // Flash: an accent wash behind the bubble, not a frame.
                        if highlighted {
                            RoundedRectangle(cornerRadius: DS.Radius.xl + 6)
                                .fill(DS.Palette.lime.opacity(0.28))
                                .padding(-6)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frameBox.rect = $0 }
                    .opacity(hidden ? 0 : 1)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3).onEnded { _ in onFocus(message, frameBox.rect) }
                    )
                    .accessibilityAction(named: "React") { onFocus(message, frameBox.rect) }
                if !mine { Spacer(minLength: 56) }
                if message.state == .failed {
                    Button { onRetry(message) } label: {
                        Image("danger-circle")
                            .font(.title3)
                            .foregroundStyle(DS.Palette.negative)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Not sent. Tap to try again.")
                }
            }
            .padding(.bottom, message.reaction != nil ? 14 : 0)
        }
        .offset(x: swipe)
        .background(alignment: .leading) {
            Image("reply")
                .font(.body.weight(.bold))
                .foregroundStyle(swipe >= replyThreshold ? DS.Palette.onLime : DS.Palette.ink)
                .frame(width: 36, height: 36)
                .background(swipe >= replyThreshold ? DS.Palette.lime : DS.Palette.white, in: .circle)
                .scaleEffect(0.5 + 0.5 * min(1, swipe / replyThreshold))
                .opacity(Double(min(1, swipe / replyThreshold)))
                .offset(x: min(swipe, replyThreshold) - 44)
                .accessibilityHidden(true)
        }
        .gesture(ReplySwipeGesture(onChanged: dragReply, onEnded: endReply))
        .accessibilityAction(named: "Reply") { onReply(message) }
        .padding(.bottom, groupedWithNext ? 0 : DS.Space.sm)
        .animation(Motion.bouncy, value: message.reaction)
    }

    /// Pixel size of a photo, to lay its bubble out in the same proportions: the size sent with it,
    /// the picture's own header, or a bundled picture.
    private func photoSize(asset: String?, data: Data?) -> CGSize? {
        if let size = message.mediaSize { return size.cgSize }
        if let data { return MessageImage.size(of: data) }
        return asset.flatMap { UIImage(named: $0)?.size }
    }

    /// Bubble size for a photo or video: 240 pt wide, the media's own height, kept between a
    /// tall 0.65 and a wide 1.8 ratio so panoramas and very tall shots stay readable.
    static func bubbleSize(_ media: CGSize?) -> CGSize {
        let width: CGFloat = 240
        guard let media, media.width > 0, media.height > 0 else { return CGSize(width: width, height: 300) }
        let ratio = min(max(media.width / media.height, 0.65), 1.8)
        return CGSize(width: width, height: (width / ratio).rounded())
    }

    /// Follows the finger once the sideways swipe has started; sliding back below the threshold
    /// cancels the reply.
    private func dragReply(_ x: CGFloat) {
        let crossedBefore = swipe >= replyThreshold
        // Rubber band past the threshold.
        swipe = x < replyThreshold ? x : replyThreshold + (x - replyThreshold) * 0.25
        if !crossedBefore && swipe >= replyThreshold { Haptics.select() }
    }

    private func endReply() {
        if swipe >= replyThreshold { onReply(message) }
        withAnimation(Motion.snappy) { swipe = 0 }
    }

    /// The message this one answers: from the thread, or what the chat service kept of it when it isn't
    /// loaded.
    private var quoted: Message? {
        guard let id = message.replyTo else { return nil }
        if let found = convo.messages.first(where: { $0.id == id }) { return found }
        return message.replyQuote.map { Message(id: id, .text($0.text), fromMe: $0.fromMe) }
    }

    private var isText: Bool { if case .text = message.content { true } else { false } }

    /// Quote in a bubble: accent bar, name, first lines. On your ink bubble the accent reads as on night.
    private func innerQuote(_ q: Message) -> some View {
        let accent = mine && colorScheme == .light ? DS.Palette.accentOnNight : DS.Palette.accentInk
        return HStack(spacing: DS.Space.sm) {
            Capsule().fill(mine ? accent : DS.Palette.lime).frame(width: 3).environment(\.colorScheme, mine ? .light : colorScheme)
            VStack(alignment: .leading, spacing: 1) {
                Text(q.fromMe ? L("You") : convo.profile.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .environment(\.colorScheme, mine ? .light : colorScheme)
                Text(q.previewText)
                    .font(.footnote)
                    .foregroundStyle(mine ? DS.Palette.white.opacity(0.75) : DS.Palette.body)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.leading, 6)
        .padding(.trailing, DS.Space.sm)
        .background(mine ? AnyShapeStyle(DS.Palette.white.opacity(0.12)) : AnyShapeStyle(DS.Palette.canvasSoft),
                    in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(q.fromMe ? L("In reply to you: \(q.previewText)") : L("In reply to \(convo.profile.name): \(q.previewText)"))
    }

    private func quote(_ q: Message) -> some View {
        HStack(spacing: DS.Space.sm) {
            Capsule().fill(DS.Palette.lime).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(q.fromMe ? L("You") : convo.profile.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DS.Palette.accentInk)
                Text(q.previewText)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.body)
                    .lineLimit(2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .frame(maxWidth: 260, alignment: .leading)
        .background(DS.Palette.white.opacity(0.6), in: .rect(cornerRadius: DS.Radius.lg))
        .padding(.bottom, -DS.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(q.fromMe ? L("In reply to you: \(q.previewText)") : L("In reply to \(convo.profile.name): \(q.previewText)"))
    }

    @ViewBuilder
    private var bubble: some View {
        switch message.content {
        case .text(let t):
            // A reply carries its quote inside the bubble, WhatsApp-style.
            VStack(alignment: .leading, spacing: 6) {
                if let q = quoted { innerQuote(q) }
                Text(t)
                    .font(.body)
                    .foregroundStyle(mine ? DS.Palette.white : DS.Palette.ink)
                    .padding(.horizontal, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(quoted == nil ? EdgeInsets(top: 10, leading: 6, bottom: 10, trailing: 6)
                                   : EdgeInsets(top: 6, leading: 6, bottom: 10, trailing: 6))
            .background(mine ? DS.Palette.ink : DS.Palette.white, in: bubbleShape)
                // Double tap: quick ❤️, like Instagram and iMessage. Only on their messages: you
                // don't react to your own.
                .onTapGesture(count: 2) { if !presentation && !mine { app.react("❤️", to: message.id, in: convo.id) } }

        case let .photo(asset, data):
            let size = Self.bubbleSize(photoSize(asset: asset, data: data))
            Button { onOpen(MediaItem(id: message.id, kind: .photo(asset: asset, data: data))) } label: {
                Group {
                    if let data {
                        MessagePhoto(id: message.id, data: data)
                    } else if let asset {
                        Photo(name: asset, side: size.width)
                    } else {
                        DS.Palette.white
                    }
                }
                // The photo's own proportions (within limits, like WhatsApp).
                .frame(width: size.width, height: size.height)
                .clipShape(.rect(cornerRadius: 20))
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .accessibilityLabel("Photo")
            .accessibilityHint("Opens it full screen")

        case let .video(url, thumb, duration):
            let size = Self.bubbleSize(message.mediaSize?.cgSize ?? thumb.flatMap(MessageImage.size(of:)))
            Button { onOpen(MediaItem(id: message.id, kind: .video(url))) } label: {
                ZStack {
                    if let thumb {
                        MessagePhoto(id: message.id, data: thumb)
                    } else if let poster = message.poster {
                        Photo(name: poster, side: size.width)
                    } else {
                        DS.Palette.night
                    }
                    Image("play")
                        .font(.title2)
                        .foregroundStyle(DS.Palette.onAccentOnNight)
                        .frame(width: 56, height: 56)
                        .background(DS.Palette.accentOnNight, in: .circle)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(.rect(cornerRadius: 20))
                .overlay(alignment: .bottomLeading) {
                    Label(duration.clock, image: "videocamera")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: .capsule)
                        .padding(10)
                }
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .accessibilityLabel("Video, \(Int(duration)) seconds")
            .accessibilityHint("Plays it full screen")

        case let .voice(url, duration, levels):
            VoicePlayer(
                url: url, duration: duration, levels: levels,
                tint: mine ? DS.Palette.white : DS.Palette.ink,
                track: mine ? DS.Palette.white.opacity(0.3) : DS.Palette.ink.opacity(0.22),
                buttonFill: mine ? DS.Palette.white : DS.Palette.lime, // your ink bubble: its inverse
                buttonGlyph: mine ? DS.Palette.ink : DS.Palette.onLime, showsSpeed: true,
                scrubbable: false // a sideways drag on a bubble is swipe-to-reply
            )
            .frame(width: 250)
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(mine ? DS.Palette.ink : DS.Palette.white, in: bubbleShape)

        case let .file(name, size, url):
            Button {
                if let url { onOpen(MediaItem(id: message.id, kind: .file(url))) }
            } label: {
                HStack(spacing: DS.Space.md) {
                    Image(name.lowercased().hasSuffix(".pdf") ? "file-text" : "file")
                        .font(.title2)
                        .foregroundStyle(mine ? DS.Palette.ink : DS.Palette.onLime)
                        .frame(width: 44, height: 52)
                        .background(mine ? DS.Palette.white : DS.Palette.lime, in: .rect(cornerRadius: DS.Radius.sm))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Text(size.formatted(.byteCount(style: .file).locale(.app)))
                            .font(.caption)
                            .opacity(0.7)
                    }
                }
                .foregroundStyle(mine ? DS.Palette.white : DS.Palette.ink)
                .padding(DS.Space.md)
                .frame(maxWidth: 260, alignment: .leading)
                .background(mine ? DS.Palette.ink : DS.Palette.white, in: bubbleShape)
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))

        case .session(let snapshot):
            // The card shows the session as it stands on the server (`SessionStore`), live; the
            // message's copy only until its row is read.
            let store = SessionStore.shared
            let row = store.record(snapshot.id)
            let s = row.flatMap(SessionProposal.init) ?? snapshot
            SessionCard(session: s, mine: row.map(store.isMine) ?? mine, profileName: convo.profile.name, chatID: convo.id,
                        busy: store.isBusy(s.id),
                        onPick: { d in
                            app.respondToSession(s.id, accept: true, pick: d)
                            onSessionSafety(s, d)
                        },
                        onDecline: { app.respondToSession(s.id, accept: false) },
                        onCounter: { onCounterSession(s) },
                        onCancel: { app.cancelSession(s.id) },
                        onSafety: { if let d = s.chosen { onSessionSafety(s, d) } })
                .onAppear { store.need(snapshot.id) }

        case let .icebreakerReply(quote, reply):
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(spacing: DS.Space.sm) {
                    Capsule().fill(DS.Palette.like).frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mine ? "Re: \(convo.profile.name)'s profile" : "Re: your profile")
                            .font(.caption.weight(.bold))
                        Text(quote).font(.footnote).lineLimit(3)
                    }
                    .opacity(0.8)
                }
                .fixedSize(horizontal: false, vertical: true)
                if !reply.isEmpty { Text(reply).font(.body) }
            }
            .foregroundStyle(mine ? DS.Palette.white : DS.Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(mine ? DS.Palette.ink : DS.Palette.white, in: bubbleShape)

        case let .photoReply(asset, reply):
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(spacing: DS.Space.sm) {
                    Capsule().fill(DS.Palette.like).frame(width: 3)
                    Photo(name: asset, side: 56)
                        .frame(width: 56, height: 72)
                        .clipShape(.rect(cornerRadius: DS.Radius.sm))
                    Text(mine ? "Liked \(convo.profile.name)'s photo" : "Liked your photo")
                        .font(.caption.weight(.bold))
                        .opacity(0.8)
                }
                if !reply.isEmpty { Text(reply).font(.body) }
            }
            .foregroundStyle(mine ? DS.Palette.white : DS.Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(mine ? DS.Palette.ink : DS.Palette.white, in: bubbleShape)
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        let big: CGFloat = 20, small: CGFloat = 6
        return UnevenRoundedRectangle(
            topLeadingRadius: big,
            bottomLeadingRadius: !mine && !groupedWithNext ? small : big,
            bottomTrailingRadius: mine && !groupedWithNext ? small : big,
            topTrailingRadius: big
        )
    }
}
