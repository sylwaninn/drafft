import SwiftUI

/// Session invite composer: sport, pitch, and one or more exact dates and times. Lets you pick
/// any other time. A live recap above the button always states exactly what will be sent.
struct ProposeSessionSheet: View {
    let profile: Profile
    let me: Profile
    let onSend: (SessionProposal) -> Void
    var sendTitle = L("Send session invite")
    var sendHint: String?

    @Environment(\.dismiss) private var dismiss
    @State private var sport: Sport
    @State private var title = ""
    @State private var discovery: SessionProposal.Discovery?
    @State private var sending = false
    /// The times offered (1 to 3). The other person picks one or suggests others.
    @State private var options: [Date]
    /// The native time sheet: a new time, or changing time #index.
    @State private var timeSheet: TimeSheetTarget?
    /// Captures the time when the sheet opens: the sheet never reads `options` by index again
    /// (removing a time while it was open read past the end and crashed).
    struct TimeSheetTarget: Identifiable {
        let index: Int?
        let date: Date?
        var id: String { "\(index ?? -1)-\(date?.timeIntervalSince1970 ?? 0)" }
    }
    /// Set when answering an invite with other times.
    private var counterTo: SessionProposal?
    @FocusState private var focus: Field?

    enum Field { case title }

    init(profile: Profile, me: Profile, sport preset: Sport? = nil,
         sendTitle: String = L("Send session invite"), sendHint: String? = nil,
         counterTo: SessionProposal? = nil,
         onSend: @escaping (SessionProposal) -> Void) {
        self.counterTo = counterTo
        self.profile = profile
        self.me = me
        self.onSend = onSend
        self.sendTitle = sendTitle
        self.sendHint = sendHint
        // Prefer a slot of the preset sport, ideally one you both already train in.
        let sharedSport = profile.sports.first { e in me.sports.contains { $0.sport == e.sport } }?.sport
        let initial = counterTo?.sport ?? preset ?? sharedSport ?? profile.sports[0].sport
        _sport = State(initialValue: initial)
        // A sport only one of you does starts as a discovery session.
        let theyDo = profile.sports.contains { $0.sport == initial }, iDo = me.sports.contains { $0.sport == initial }
        _discovery = State(initialValue: counterTo?.discovery ?? (theyDo && iDo ? nil : (theyDo ? .theyTeach : .iTeach)))
        if let counterTo {
            _title = State(initialValue: counterTo.title)
        }
        // Nothing picked yet: no time card until the person adds one.
        _options = State(initialValue: [])
    }

    // MARK: Derived

    /// Sports you do that they don't: you can introduce them.
    private var youTeach: [Sport] { me.sports.map(\.sport).filter { s in !profile.sports.contains { $0.sport == s } } }
    /// Sports they do that you don't: they can show you.
    private var theyTeach: [Sport] { profile.sports.map(\.sport).filter { s in !me.sports.contains { $0.sport == s } } }

    private var pitchIdeas: [String] {
        switch discovery {
        case .iTeach: [L("First \(sport.inSentence) session? I'll show you the basics."),
                       L("Try \(sport.inSentence) with me, zero pressure?"),
                       L("Beginner-friendly \(sport.inSentence), I'll bring the gear?")]
        case .theyTeach: [L("Teach me \(sport.inSentence)? I'm a total beginner."),
                          L("My first \(sport.inSentence) session, be gentle?"),
                          L("Show me your \(sport.inSentence) moves?")]
        case nil: SessionProposal.titleIdeas(for: sport)
        }
    }

    private func select(_ s: Sport, discovery d: SessionProposal.Discovery?) {
        Haptics.select()
        sport = s
        discovery = d
    }

    private let maxOptions = 3

    /// What gets sent: the options in time order.
    private var outgoingOptions: [Date] { options.sorted() }
    private var sessionDate: Date { outgoingOptions.first ?? .now }
    private var isCounter: Bool { counterTo != nil }

    private func compose(_ index: Int?) {
        Haptics.select()
        timeSheet = TimeSheetTarget(index: index, date: index.flatMap { options.indices.contains($0) ? options[$0] : nil })
    }

    private func removeTime(_ date: Date) {
        withAnimation(Motion.snappy) { options.removeAll { abs($0.timeIntervalSince(date)) < 60 } }
    }

    /// Two times that are the same.
    private var hasDuplicate: Bool { Set(options.map { Int($0.timeIntervalSince1970 / 60) }).count < options.count }

    /// A picked time that has since passed.
    private var hasPast: Bool { options.contains { $0 < .now } }

    private var canSend: Bool { !sending && !options.isEmpty && !hasPast && !hasDuplicate }

    /// The line under the send button: why it's disabled (red for a real error), or the hint.
    private var sendReason: (text: String, isError: Bool)? {
        if options.isEmpty { return (text: L("Pick at least one time to send."), isError: false) }
        if hasPast { return (text: L("One of your times has passed."), isError: true) }
        if hasDuplicate { return (text: L("Two of your times are the same."), isError: true) }
        return sendHint.map { (text: $0, isError: false) }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            FocusScrollView {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    header
                    if let counterTo {
                        // Other times: the session stays as it is, only the times change.
                        fixedSession(counterTo)
                    } else {
                        block("Sport", icon: "running") { sportPicker }
                        block("Pitch it", icon: "chat-round-quote", trailing: "Optional") { titlePicker }
                    }
                    block("When", icon: "calendar", trailing: "Up to \(maxOptions) times") { slotsEditor }
                    block("Meet safely", icon: "shield-check") { SafetyTipRows() }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.sm)
                .padding(.bottom, DS.Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.Palette.canvasSoft)
            .blurredNavigationEdge()
            .bottomBar { footer }
            .toolbar {
                // Close sits on the right, like every other sheet in the app.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", image: .icon("close")) { dismiss() }
                }
            }
            .animation(Motion.select, value: sport)
            .animation(Motion.snappy, value: options)
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(sending)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: DS.Space.md) {
            Avatar(name: profile.portrait, size: 52, ring: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(counterTo == nil ? "Train with \(profile.name)" : "Suggest other times")
                    .font(.display(22, relativeTo: .title2))
                    .foregroundStyle(DS.Palette.ink)
                    // Long names wrap to a second line instead of being cut.
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(counterTo == nil ? "Meet up and move together." : "Offer a few times that work for you.")
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.body)
            }
        }
        // Nothing floats on the sage ground: the header is a white block like the sections below.
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }

    /// Every sport either of you does, once, tagged by who knows it. Shared sports come first,
    /// then the ones they could show you, then the ones you could show them. Picking a tile
    /// sets the discovery mode on its own, so there's nothing else to choose.
    private var sportTiles: [(sport: Sport, discovery: SessionProposal.Discovery?)] {
        let shared = profile.sports.map(\.sport).filter { s in me.sports.contains { $0.sport == s } }
        return shared.map { ($0, nil) } + theyTeach.map { ($0, .theyTeach) } + youTeach.map { ($0, .iTeach) }
    }

    /// The faces on a sport tile: you then them for a shared sport, otherwise whoever does it.
    private func faces(for d: SessionProposal.Discovery?) -> [String] {
        switch d {
        case nil: [me.portrait, profile.portrait]
        case .theyTeach: [profile.portrait]
        case .iTeach: [me.portrait]
        }
    }

    /// For VoiceOver only: on screen, each sport shows the faces of who does it.
    private func spokenTag(for d: SessionProposal.Discovery?) -> String {
        switch d {
        case nil: L("you both do it")
        case .theyTeach: L("\(profile.name) could show you")
        case .iTeach: L("you could show \(profile.name)")
        }
    }

    private var sportPicker: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.sm), GridItem(.flexible(), spacing: DS.Space.sm)],
                  spacing: DS.Space.sm) {
            ForEach(sportTiles, id: \.sport) { tile in
                sportTile(tile.sport, discovery: tile.discovery)
            }
        }
    }

    private func sportTile(_ s: Sport, discovery d: SessionProposal.Discovery?) -> some View {
        let on = sport == s && discovery == d
        return Button { select(s, discovery: d) } label: {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                HStack(alignment: .top) {
                    Image(s.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.ink)
                        .frame(width: 40, height: 40)
                        .background(on ? AnyShapeStyle(DS.Palette.onLimeWash) : AnyShapeStyle(DS.Palette.canvas), in: .circle)
                    Spacer(minLength: 0)
                    CheckDisc(isOn: on, onLimeFill: true)
                }
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text(s.name)
                        .font(.headline)
                        .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.ink)
                        .lineLimit(2) // sport names are never cut
                        .minimumScaleFactor(0.9)
                    // Who does it, in faces: both of you, only them, or only you. No words needed.
                    Faces(portraits: faces(for: d), ringColor: on ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(DS.Palette.canvasSoft))
                        .accessibilityHidden(true)
                }
            }
            .padding(DS.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Selected = solid accent fill, like a chip: reads in light and dark, no frame.
            .background(on ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(DS.Palette.canvasSoft), in: .rect(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityLabel("\(s.name), \(spokenTag(for: d))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Read-only recap of the invite being answered: sport and pitch are theirs, only times change.
    private func fixedSession(_ original: SessionProposal) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            // The sport as a small lime tag; the pitch gets the full width below it.
            HStack(spacing: 6) {
                Image(original.sport.symbol)
                    .font(.footnote.weight(.bold))
                Text(original.discovery == nil ? original.sport.name : L("\(original.sport.name) discovery"))
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(DS.Palette.onAccentOnNight)
            .padding(.horizontal, DS.Space.md)
            .frame(minHeight: 30)
            .background(DS.Palette.accentOnNight, in: .capsule)

            Text(original.displayTitle)
                .font(.displayBold(26, relativeTo: .title2))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("They offered")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.55))
                ForEach(original.options, id: \.self) { d in
                    Text(slotText(d))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                        .strikethrough(color: .white.opacity(0.4))
                }
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading).nightSurface()
        // A sheet: plain night.
        .background(DS.Palette.night, in: .rect(cornerRadius: DS.Radius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.xl)
                .strokeBorder(DS.Palette.blockEdge, lineWidth: 1)
        }
    }

    private func slotText(_ d: Date) -> String {
        L("\(d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(.app))) at \(d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app)))")
    }

    /// Up to three time cards. "Add a time" and each card open the native date and time sheet.
    private var slotsEditor: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, d in timeCard(i, d) }
                if options.count < maxOptions { addCard }
                ForEach(0..<max(0, maxOptions - options.count - 1), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, minHeight: 112)
                }
            }
            // A time that has passed is explained under the send button.
            Text(options.isEmpty ? "Offer up to \(maxOptions) times. \(profile.name) picks one, or suggests others."
                 : "Tap a time to change it. \(profile.name) picks one, or suggests others.")
                .font(.footnote)
                .foregroundStyle(DS.Palette.mute)
        }
        .sheet(item: $timeSheet) { target in
            Group {
                SessionTimeSheet(initial: target.date,
                                 taken: options.filter { o in target.date.map { abs(o.timeIntervalSince($0)) >= 60 } ?? true },
                                 onSave: { d in
                                     withAnimation(Motion.bouncy) {
                                         if let old = target.date { options.removeAll { abs($0.timeIntervalSince(old)) < 60 } }
                                         options.append(d)
                                         options.sort()
                                     }
                                 },
                                 onRemove: target.date.map { old in { removeTime(old) } })
            }
            .sheetSurface()
        }
    }

    /// A picked time: weekday, big day number, month, and the hour. Tap to change it.
    private func timeCard(_ i: Int, _ d: Date) -> some View {
        Button { compose(i) } label: {
            VStack(spacing: 2) {
                Text(Calendar.current.isDateInToday(d) ? L("Today") : d.formatted(.dateTime.weekday(.abbreviated).locale(.app)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DS.Palette.body)
                Text(d.formatted(.dateTime.day().locale(.app)))
                    .font(.display(30, relativeTo: .title))
                    .foregroundStyle(DS.Palette.ink)
                Text(d.formatted(.dateTime.month(.abbreviated).locale(.app)))
                    .font(.caption)
                    .foregroundStyle(DS.Palette.body)
                Text(d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app)))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.horizontal, DS.Space.sm)
                    .frame(minHeight: 26)
                    .background(DS.Palette.canvas, in: .capsule)
                    .padding(.top, DS.Space.xs)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .background(DS.Palette.canvasSoft, in: .rect(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .accessibilityLabel("Time \(i + 1), \(slotText(d))")
        .accessibilityHint("Change or remove this time")
    }

    private var addCard: some View {
        Button { compose(nil) } label: {
            VStack(spacing: DS.Space.xs) {
                Image("add")
                    .font(.title3.weight(.bold))
                Text(options.isEmpty ? "Add a time" : "Add another")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(DS.Palette.accentInk)
            .frame(maxWidth: .infinity, minHeight: 112)
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(DS.Palette.ink.opacity(0.22), style: .init(lineWidth: 1.5, dash: [6, 5]))
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
    }

    // MARK: Pitch (a one-line hook for the session)

    private var titlePicker: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            // Placeholder drawn as wrapping text in the same stack, so the field grows to fit it
            // (a vertical TextField would truncate a long prompt).
            ZStack(alignment: .topLeading) {
                if title.isEmpty {
                    Text(pitchIdeas[0])
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Palette.mute)
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextField("", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.body.weight(.semibold))
                    .focused($focus, equals: .title)
                    .revealsOnFocus(focus == .title)
                    .submitLabel(.done)
                    .accessibilityLabel("Pitch")
            }
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, 13)
                .background(DS.Palette.canvasSoft, in: .rect(cornerRadius: DS.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .strokeBorder(focus == .title ? DS.Palette.ink : .clear, lineWidth: 1.5)
                }
                .overlay(alignment: .topTrailing) {
                    if !title.isEmpty {
                        Button { withAnimation(Motion.snappy) { title = "" } } label: {
                            Image("close-circle").foregroundStyle(DS.Palette.mute)
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .accessibilityLabel("Clear pitch")
                    }
                }
                .animation(Motion.snappy, value: focus)

            Text("Or steal one of these")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.mute)
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                ForEach(pitchIdeas, id: \.self) { idea in
                    let on = title == idea
                    Button {
                        Haptics.select()
                        withAnimation(Motion.select) { title = on ? "" : idea }
                    } label: {
                        // Icon sits on the first line's baseline, even when the idea wraps.
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                            Image(on ? "check" : "stars")
                                .font(.footnote.weight(.bold))
                                .frame(width: 16)
                                .contentTransition(.symbolEffect(.replace))
                            Text(idea)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.ink)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.md)
                        .frame(minHeight: 44)
                        .background(on ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(DS.Palette.canvasSoft), in: .rect(cornerRadius: DS.Radius.md))
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.98))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .id("\(sport)-\(String(describing: discovery))") // fresh ideas when the sport or discovery changes
            .transition(.opacity)
        }
    }

    /// Recap of exactly what will be sent, then the action.
    private var footer: some View {
        VStack(spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Image(sport.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Palette.onLime)
                    .frame(width: 40, height: 40)
                    .background(DS.Palette.lime, in: .circle)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    let what = discovery == nil ? sport.name : L("\(sport.name) discovery")
                    let day = sessionDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(.app))
                    let time = sessionDate.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app))
                    Text(options.isEmpty ? L("\(what), no time yet") : outgoingOptions.count > 1
                         ? L("\(what), \(outgoingOptions.count) time options")
                         : L("\(what), \(day) at \(time)"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DS.Palette.ink)
                        .rollingDigits(wording: options.isEmpty ? "none" : outgoingOptions.count > 1 ? "many" : "\(what)\(day)".wording)
                    Text(title.isEmpty ? (isCounter ? L("Same session, new times") : L("No pitch yet")) : title)
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.body)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .animation(Motion.snappy, value: sessionDate)
            .animation(Motion.snappy, value: options)
            .accessibilityElement(children: .combine)

            Button(action: send) {
                if sending {
                    Label("Sent", image: "check")
                } else {
                    SendLabel(title: sendTitle, count: options.count)
                }
            }
            .buttonStyle(.drafftPrimary)
            .disabled(!canSend)
            .draftTrail(RoundedRectangle(cornerRadius: DS.Radius.xl), step: CGSize(width: -6, height: 0))
            .padding(.leading, 12)

            // Keeps its height when empty, so the button never moves.
            Text(sendReason?.text ?? " ")
                .font(.caption)
                .foregroundStyle(sendReason?.isError == true ? DS.Palette.negative : DS.Palette.body)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.lg)
        .padding(.bottom, DS.Space.sm)
    }

    private func send() {
        guard canSend else { return }
        focus = nil
        Haptics.success()
        withAnimation(Motion.bouncy) { sending = true }
        let proposal = SessionProposal(sport: sport, options: outgoingOptions,
                                       title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                       note: "", discovery: discovery)
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            onSend(proposal)
            dismiss()
        }
    }

    // MARK: Chrome

    /// White block with its own small title; nothing floats on the sage ground.
    private func block<C: View>(_ title: LocalizedStringKey, icon: String, trailing: LocalizedStringKey? = nil,
                                @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Image(icon)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(DS.Palette.ink)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DS.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let trailing {
                    Text(trailing).font(.footnote).foregroundStyle(DS.Palette.mute)
                }
            }
            content()
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }
}

/// Small overlapping portraits of who does a sport ("you both", "them", "you"), said without text.
/// Each face sits in a ring of the tile's own colour, so an overlap reads as a cut, not a border.
private struct Faces: View {
    let portraits: [String]
    let ringColor: AnyShapeStyle
    private let side: CGFloat = 22

    var body: some View {
        HStack(spacing: -7) {
            ForEach(Array(portraits.enumerated()), id: \.offset) { _, name in
                Photo(name: name, side: side)
                    .frame(width: side, height: side)
                    .clipShape(.circle)
                    .padding(2)
                    .background(ringColor, in: .circle)
            }
        }
    }
}

/// The send button's label, on one line in every language: the count of times goes when it doesn't
/// fit (the recap above the button already says how many).
private struct SendLabel: View {
    let title: String
    let count: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Label(count > 1 ? L("\(title) (\(count) times)") : title, image: "plain")
            Label(title, image: "plain")
        }
    }
}
