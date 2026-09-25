import SwiftUI

struct ConversationsView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var path: [String] = []
    @State private var scrollOffset: CGFloat = 0

    private var newMatches: [Conversation] { app.conversations.filter { $0.messages.isEmpty } }
    /// The list's own side margin (inset grouped, iPhone), where its cards start.
    private static let edge: CGFloat = 20
    private var threads: [Conversation] {
        app.conversations.filter { !$0.messages.isEmpty }
            .filter { query.isEmpty || $0.profile.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !newMatches.isEmpty && query.isEmpty {
                    // Edge to edge: no section margin or card, so the row scrolls to the screen's
                    // edges. The title sits in the same row as the avatars, on the same margin, so
                    // the two always line up (a section header has margins of its own).
                    Section {
                        VStack(alignment: .leading, spacing: DS.Space.sm) {
                            Text("New matches")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(DS.Palette.body)
                                .padding(.horizontal, Self.edge)
                                .accessibilityAddTraits(.isHeader)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: DS.Space.sm) {
                                    ForEach(newMatches) { c in
                                        Button { path.append(c.id) } label: {
                                            VStack(spacing: DS.Space.xs + 2) {
                                                Avatar(name: c.profile.portrait, size: 68)
                                                // A name is the person's own: two lines, then cut.
                                                Text(c.profile.name)
                                                    .font(.footnote.weight(.semibold))
                                                    .foregroundStyle(DS.Palette.ink)
                                                    .multilineTextAlignment(.center)
                                                    .lineLimit(2)
                                                    // design-lint: allow truncation - a person's name (content, not copy), asked cut after two lines
                                                    .truncationMode(.tail)
                                                    .frame(width: 72, alignment: .top)
                                            }
                                        }
                                        .buttonStyle(PressScaleStyle())
                                        .accessibilityLabel("New match, \(c.profile.name). Start chatting")
                                    }
                                }
                                .padding(.horizontal, Self.edge)
                                .padding(.vertical, DS.Space.xs)
                            }
                            .scrollClipDisabled()
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .listSectionMargins(.horizontal, 0)
                    // No list lines above or below the row: it isn't a card.
                    .listSectionSeparator(.hidden)
                }

                Section {
                    if threads.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "No chats yet" : "No chats match “\(query)”",
                                               systemImage: "bubble.left.and.bubble.right",
                                               description: Text(query.isEmpty
                                                                 ? (newMatches.isEmpty ? "Match with someone on Discover to start chatting." : "Say hi to a new match to start chatting.")
                                                                 : "Try a different name."))
                            // Inside the white list card, never loose on the sage page.
                            .listRowBackground(Rectangle().fill(DS.Palette.canvas))
                    }
                    ForEach(threads) { c in
                        NavigationLink(value: c.id) { ConversationRow(convo: c) }
                            .listRowBackground(Rectangle().fill(DS.Palette.canvas))
                            .swipeActions(edge: .trailing) {
                                Button(c.muted ? "Unmute" : "Mute", systemImage: c.muted ? "bell" : "bell.slash") {
                                    app.toggleMute(c.id)
                                }
                                    // Stays dark in dark mode too, so the white label keeps its contrast.
                                    .tint(DS.Palette.nightRaised)
                            }
                            .swipeActions(edge: .leading) {
                                Button(c.isUnread ? "Read" : "Unread", systemImage: c.isUnread ? "envelope.open" : "envelope.badge") {
                                    if c.isUnread { app.markRead(c.id) } else { app.markUnread(c.id) }
                                }
                                .tint(DS.Palette.night)
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DS.Palette.canvasSoft)
            .listSectionSpacing(.compact)
            .contentMargins(.top, DS.Space.xs, for: .scrollContent)
            .trackingScrollOffset($scrollOffset)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .topBar {
                TabHeader(offset: scrollOffset, search: $query, searchPrompt: L("Search chats")) {
                    TabTitle(text: L("Chats"))
                }
            }
            .navigationDestination(for: String.self) { id in
                ChatView(conversationID: id)
            }
            .animation(Motion.snappy, value: app.conversations.map(\.id))
        }
        // Decided here, on the path: it flips back to visible as soon as Back begins.
        .toolbarVisibility(path.isEmpty ? .visible : .hidden, for: .tabBar)
        .onChange(of: app.chatRequest) { _, id in
            if let id { show(id) }
        }
        .onAppear {
            if let id = app.chatRequest { show(id) }
        }
    }

    private func show(_ id: String) {
        if path.last != id { path = [id] }
        app.chatRequest = nil
    }
}

struct ConversationRow: View {
    let convo: Conversation

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Avatar(name: convo.profile.portrait, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                    Text(convo.profile.name)
                        .font(.headline)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if convo.muted {
                        Image(systemName: "bell.slash")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.Palette.body)
                            .accessibilityHidden(true) // the row's value says it
                    }
                    Spacer()
                    if let d = convo.lastMessage?.date {
                        Text(d.chatStamp)
                            .font(.footnote.weight(convo.isUnread ? .semibold : .regular))
                            .foregroundStyle(convo.isUnread ? DS.Palette.ink : DS.Palette.mute)
                    }
                }
                HStack(alignment: .top) {
                    Group {
                        if convo.isTyping {
                            HStack(spacing: 6) {
                                TypingDots(color: DS.Palette.accentInk, size: 5)
                                    .accessibilityHidden(true) // the word says it
                                Text("Typing").foregroundStyle(DS.Palette.accentInk)
                            }
                        } else if let m = convo.lastMessage {
                            preview(m)
                        }
                    }
                    .font(.subheadline.weight(convo.isUnread ? .semibold : .regular))
                    .lineLimit(2)
                    Spacer(minLength: DS.Space.sm)
                    if convo.unread > 0 {
                        Text("\(convo.unread)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            // Muted chats get a quiet badge instead of the accent.
                            .foregroundStyle(convo.muted ? DS.Palette.ink : DS.Palette.onLime)
                            .frame(minWidth: 22, minHeight: 22)
                            .padding(.horizontal, 4)
                            .background(convo.muted ? DS.Palette.ink.opacity(0.12) : DS.Palette.lime, in: .capsule)
                            .contentTransition(.numericText())
                            .accessibilityLabel("\(convo.unread) unread")
                    } else if convo.markedUnread {
                        // Marked by hand: a dot, the badge's height, no count.
                        Circle()
                            .fill(convo.muted ? DS.Palette.ink.opacity(0.12) : DS.Palette.lime)
                            .frame(width: 22, height: 22)
                            .accessibilityLabel("Marked as unread")
                    }
                }
            }
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityValue(convo.muted ? "Muted" : "")
    }

    /// Grey "You: ", then the content icon, then the text: one Text so it wraps as a paragraph.
    private func preview(_ m: Message) -> Text {
        let author = Text(m.fromMe ? "You: " : "").foregroundStyle(DS.Palette.mute)
        let icon = (m.previewIcon.map { Text("\(Image(systemName: $0)) ") } ?? Text("")).foregroundStyle(DS.Palette.body)
        let text = Text(m.previewText).foregroundStyle(convo.isUnread ? DS.Palette.ink : DS.Palette.body)
        return Text("\(author)\(icon)\(text)")
    }
}

extension Message {
    var previewIcon: String? {
        switch content {
        case .photo, .photoReply: "photo"
        case .video: "video.fill"
        case .voice: "waveform"
        case .file: "doc.fill"
        case .session: "flag.2.crossed" // the Sessions tab icon
        default: nil
        }
    }
}

extension Date {
    var chatStamp: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app)) }
        if cal.isDateInYesterday(self) { return L("Yesterday") }
        return formatted(.dateTime.weekday(.abbreviated).locale(.app))
    }
}

struct TypingDots: View {
    var color: Color = DS.Palette.body
    var size: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                        .opacity(reduceMotion ? 0.7 : 0.35 + 0.65 * max(0, sin(t * 6 - Double(i) * 0.9)))
                        .offset(y: reduceMotion ? 0 : -size * 0.35 * max(0, sin(t * 6 - Double(i) * 0.9)))
                }
            }
        }
        .accessibilityLabel("Typing")
    }
}
