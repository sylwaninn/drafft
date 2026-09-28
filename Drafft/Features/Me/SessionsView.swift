import SwiftUI

/// Sessions tab: the next confirmed session as a feature card, invites that still need a time,
/// then everything else coming up. From the server (`upcoming_sessions`, `SessionStore`), live.
struct SessionsView: View {
    @Environment(AppModel.self) private var app
    @State private var scrollOffset: CGFloat = 0
    /// Chats open inside this tab, so Back returns to Sessions.
    @State private var path: [ChatRoute] = []

    /// One upcoming session, with who it's with and whose turn it is.
    private struct Item {
        let session: SessionProposal
        let chatID: String
        let name: String
        let photo: String
        let mine: Bool
    }

    private var items: [Item] {
        let store = SessionStore.shared
        return store.upcoming.compactMap { row in
            guard let session = SessionProposal(row) else { return nil }
            let chatID = row.matchID.uuidString.lowercased()
            let profile = app.conversation(chatID)?.profile
            return Item(session: session, chatID: chatID, name: row.partner?.name ?? profile?.name ?? "",
                        photo: row.partner?.photo ?? profile?.portrait ?? "", mine: store.isMine(row))
        }
    }
    private var confirmed: [Item] { items.filter { $0.session.status == .accepted } }
    private var pending: [Item] { items.filter { $0.session.status == .pending } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: DS.Space.md) {
                    if confirmed.isEmpty && pending.isEmpty {
                        emptyState
                    } else {
                        if let next = confirmed.first { nextUp(next) }
                        if !pending.isEmpty {
                            group(L("Finding a time")) {
                                ForEach(Array(pending.enumerated()), id: \.element.session.id) { i, item in
                                    pendingRow(item)
                                    if i < pending.count - 1 { separator }
                                }
                            }
                        }
                        let later = Array(confirmed.dropFirst())
                        if !later.isEmpty {
                            group(L("Coming up")) {
                                ForEach(Array(later.enumerated()), id: \.element.session.id) { i, item in
                                    confirmedRow(item)
                                    if i < later.count - 1 { separator }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xxl)
            }
            .contentMargins(.top, DS.Space.xs, for: .scrollContent)
            .trackingScrollOffset($scrollOffset)
            // Read again whenever the tab shows (Realtime and foreground keep it current meanwhile).
            .task { await SessionStore.shared.refresh() }
            .background(DS.Palette.canvasSoft)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: ChatRoute.self) { r in
                ChatView(conversationID: r.chatID, focusSession: r.sessionID)
            }
            .topBar {
                TabHeader(offset: scrollOffset) { TabTitle(text: L("Sessions")) }
            }
        }
        .toolbarVisibility(path.isEmpty ? .visible : .hidden, for: .tabBar)
    }

    // MARK: Next up

    private func nextUp(_ item: Item) -> some View {
        let s = item.session
        return VStack(alignment: .leading, spacing: DS.Space.xl) {
            HStack(alignment: .center) {
                Text(countdown(to: s.date))
                    .font(.caption.weight(.heavy))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(DS.Palette.onLime)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DS.Palette.lime, in: .capsule)
                Spacer()
                Image(systemName: s.sport.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Palette.night)
                    .frame(width: 44, height: 44)
                    .background(.white, in: .circle)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text(s.displayTitle)
                    .font(.display(30, relativeTo: .title))
                    .displayLeading(30)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(s.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.app))) at \(s.timeText)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.lime)
            }

            HStack(spacing: DS.Space.sm) {
                Avatar(name: item.photo, size: 36)
                Text("With \(item.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

            HStack(spacing: DS.Space.sm) {
                Button { path.append(ChatRoute(chatID: item.chatID, sessionID: s.id)) } label: {
                    Label("Open chat", systemImage: "bubble.left.fill")
                }
                .buttonStyle(.drafftPrimary)
                .draftTrail(RoundedRectangle(cornerRadius: DS.Radius.xl), step: CGSize(width: -6, height: 0))
                .padding(.leading, 12)
                CalendarButton(session: s, partner: item.name, chatID: item.chatID, compact: true)
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .draftBlock(DS.Palette.night)
        .accessibilityElement(children: .contain)
    }

    /// "Today", "Tomorrow", "In 3 days", or the date when it's further out.
    private func countdown(to date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L("Today") }
        if cal.isDateInTomorrow(date) { return L("Tomorrow") }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
        return days < 7 ? L("In \(days) days") : L("Next up")
    }

    // MARK: Rows

    private func dateColumn(_ d: Date) -> some View {
        VStack(spacing: 0) {
            Text(d.formatted(.dateTime.weekday(.abbreviated).locale(.app)))
                .font(.caption.weight(.bold))
                .foregroundStyle(DS.Palette.body)
            Text(d.formatted(.dateTime.day().locale(.app)))
                .font(.display(26, relativeTo: .title2))
                .foregroundStyle(DS.Palette.ink)
        }
        .frame(width: 44)
    }

    private func pendingRow(_ item: Item) -> some View {
        // Their invite waiting on you, or yours waiting on them.
        let s = item.session, mine = item.mine
        return Button { path.append(ChatRoute(chatID: item.chatID, sessionID: s.id)) } label: {
            HStack(spacing: DS.Space.md) {
                Avatar(name: item.photo, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(s.sport.name) with \(item.name)")
                        .font(.headline)
                        .foregroundStyle(DS.Palette.ink)
                    Text(s.options.count > 1 ? "\(s.options.count) times offered" : "\(s.date.formatted(.dateTime.weekday(.abbreviated).day().locale(.app))), \(s.timeText)")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.body)
                }
                Spacer(minLength: DS.Space.sm)
                Text(mine ? "Waiting" : "Your turn")
                    .font(.caption.weight(.heavy))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(mine ? DS.Palette.body : DS.Palette.onLime)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(mine ? AnyShapeStyle(DS.Palette.canvasSoft) : AnyShapeStyle(DS.Palette.lime), in: .capsule)
            }
            .padding(.vertical, DS.Space.md)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func confirmedRow(_ item: Item) -> some View {
        let s = item.session
        return Button { path.append(ChatRoute(chatID: item.chatID, sessionID: s.id)) } label: {
            HStack(spacing: DS.Space.md) {
                dateColumn(s.date)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.displayTitle)
                        .font(.headline)
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(2)
                    Text("\(s.timeText) with \(item.name)")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.body)
                }
                Spacer(minLength: DS.Space.sm)
                Image(systemName: s.sport.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Palette.onLime)
                    .frame(width: 36, height: 36)
                    .background(DS.Palette.lime, in: .circle)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, DS.Space.md)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Chrome

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(DS.Palette.mute)
                .padding(.top, DS.Space.lg)
                .padding(.bottom, DS.Space.xs)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, DS.Space.xs)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }

    private var separator: some View {
        Rectangle().fill(DS.Palette.hairline).frame(height: 1).padding(.leading, 56)
    }

    private var emptyState: some View {
        EmptyStateView(art: .sessions, title: "No sessions yet.",
                       message: "Open a chat with a match and propose a session. Confirmed ones show up here.") {
            Button("Go to chats") { app.tab = .chats }
                .buttonStyle(.drafftPrimaryFit)
        }
        // The middle of the visible page, under the header.
        .containerRelativeFrame(.vertical) { h, _ in h * 0.8 }
    }
}
