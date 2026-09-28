import SwiftUI

/// Chrome for read-only sheets from You (nothing to submit, so no pinned button):
/// inline title, close on the right, white blocks on sage.
struct MeInfoSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.md) { content }
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.top, DS.Space.sm)
                    .padding(.bottom, DS.Space.xxl)
            }
            .background(DS.Palette.canvasSoft)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .blurredNavigationEdge()
        }
        .presentationDragIndicator(.visible)
    }
}

/// Round icon badge used by the rows below.
private struct RowBadge: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(DS.Palette.ink)
            .frame(width: 36, height: 36)
            .background(DS.Palette.canvasSoft, in: .circle)
            .accessibilityHidden(true)
    }
}

private struct RowSeparator: View {
    var body: some View {
        Rectangle().fill(DS.Palette.hairline).frame(height: 1).padding(.leading, 52)
    }
}

// MARK: - Blocked people

struct BlockedPeopleSheet: View {
    @Environment(AppModel.self) private var app
    @State private var pending: Profile?

    private var blocked: [Profile] { app.blocked }

    var body: some View {
        MeInfoSheet(title: L("Blocked people")) {
            if blocked.isEmpty {
                SheetBlock {
                    RowBadge(symbol: "hand.raised.fill")
                    Text("No one blocked.")
                        .font(.headline)
                        .foregroundStyle(DS.Palette.ink)
                    Text("You can block someone from their profile or a chat.")
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            } else {
                SheetBlock {
                    Text("They can't see your profile or message you, and you won't see them.")
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 0) {
                        ForEach(Array(blocked.enumerated()), id: \.element.id) { index, person in
                            if index > 0 { RowSeparator() }
                            row(person)
                        }
                    }
                }
            }
        }
        .drafftConfirm(isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                       icon: "hand.raised.slash.fill",
                       title: pending.map { L("Unblock \($0.name)?") } ?? L("Unblock?"),
                       message: L("You'll see each other in Discover again. Your old chat doesn't come back."),
                       actions: unblockActions)
    }

    private var unblockActions: [ConfirmAction] {
        guard let person = pending else { return [] }
        return [ConfirmAction(title: L("Unblock")) { unblock(person) }]
    }

    private func unblock(_ person: Profile) {
        Haptics.success()
        app.unblock(person)
    }

    private func row(_ person: Profile) -> some View {
        HStack(spacing: DS.Space.md) {
            Photo(name: person.portrait, side: 36)
                .frame(width: 36, height: 36)
                .clipShape(.circle)
                .accessibilityHidden(true)
            Text(person.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.sm)
            Button {
                Haptics.tap()
                pending = person
            } label: {
                Text("Unblock")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.horizontal, DS.Space.md)
                    .frame(minHeight: 36)
                    .background(DS.Palette.canvasSoft, in: .capsule)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(PressScaleStyle(scale: 0.94))
            .accessibilityLabel("Unblock \(person.name)")
        }
        .padding(.vertical, DS.Space.xs)
        .transition(.opacity)
    }
}

// MARK: - Safety tips

/// One set of safety advice, used everywhere: the Safety tips page, the session invite and the
/// session confirmation. Same words in each place, so people learn them.
enum SafetyTips {
    typealias Tip = (icon: String, title: String, detail: String)

    /// Before and during a first session.
    static var meeting: [Tip] { [
        ("figure.run", L("Meet where people train"),
         L("A busy track, park, gym or club session, with others around.")),
        ("person.2.fill", L("Tell a friend"),
         L("Share who you're meeting, where and when. Check in with them after.")),
        ("bicycle", L("Get there on your own"),
         L("Make your own way there and back. Your address can wait.")),
        ("map.fill", L("Stay on routes you know"),
         L("For a run or a ride, pick a busy route in daylight and keep your phone charged.")),
        ("bubble.left.and.bubble.right.fill", L("Keep the chat in drafft"),
         L("Stay in the app until you know them. Never send money.")),
        ("door.left.hand.open", L("Trust your gut"),
         L("You can end a session anytime, no explanation needed."))
    ] }

    static var report: Tip { ("flag.fill", L("Report anything off"),
                              L("Tap Report or block on their profile or in the chat. Reports are confidential.")) }
}

/// Tips as rows: round badge, title, one line of detail, hairlines between.
struct SafetyTipRows: View {
    var tips: [SafetyTips.Tip] = SafetyTips.meeting

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tips.enumerated()), id: \.element.title) { index, tip in
                if index > 0 { RowSeparator() }
                HStack(alignment: .top, spacing: DS.Space.md) {
                    RowBadge(symbol: tip.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(branded: tip.title, font: .subheadline.weight(.semibold), brandWeight: .heavy)
                            .foregroundStyle(DS.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(tip.detail)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Space.md)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct SafetyTipsSheet: View {
    var body: some View {
        MeInfoSheet(title: L("Safety tips")) {
            SheetBlock(title: L("Meeting someone for the first time")) {
                SafetyTipRows(tips: SafetyTips.meeting + [SafetyTips.report])
            }
        }
    }
}

/// Shown right after you confirm a session time: the plan in one line, then the safety tips.
struct SessionSafetySheet: View {
    let session: SessionProposal
    let date: Date
    let partner: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.md) {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Label("Session confirmed", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.accentOnNight)
                        Text("\(session.sport.name) with \(partner)")
                            .font(.display(28, relativeTo: .title))
                            .displayLeading(28)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.app))) at \(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app)))")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(DS.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Palette.night, in: .rect(cornerRadius: DS.Radius.xl))
                    .nightSurface()
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.xl)
                            .strokeBorder(DS.Palette.blockEdge, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .accessibilityElement(children: .combine)

                    SheetBlock(title: L("Before you go")) {
                        SafetyTipRows()
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.sm)
                .padding(.bottom, DS.Space.xl)
            }
            .background(DS.Palette.canvasSoft)
            .navigationTitle("Meet safely")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .blurredNavigationEdge()
            .bottomBar {
                Button("Got it") { dismiss() }
                    .buttonStyle(.drafftPrimary)
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.top, DS.Space.md)
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Legal documents

struct LegalDocsListSheet: View {
    @State private var open: LegalDoc?

    private func icon(_ doc: LegalDoc) -> String {
        switch doc {
        case .terms: "doc.text.fill"
        case .privacy: "lock.fill"
        case .community: "person.3.fill"
        }
    }

    var body: some View {
        MeInfoSheet(title: L("Terms & privacy")) {
            SheetBlock {
                VStack(spacing: 0) {
                    ForEach(Array(LegalDoc.allCases.enumerated()), id: \.element) { index, doc in
                        if index > 0 { RowSeparator() }
                        Button {
                            Haptics.tap()
                            open = doc
                        } label: {
                            HStack(spacing: DS.Space.md) {
                                RowBadge(symbol: icon(doc))
                                Text(doc.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(DS.Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: DS.Space.sm)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(DS.Palette.mute)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, DS.Space.md)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        // Over this list, so closing a document comes back here.
        .sheet(item: $open) { item in Group { LegalDocSheet(doc: item) }.sheetSurface() }
    }
}
