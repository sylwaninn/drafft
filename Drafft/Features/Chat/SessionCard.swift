import SwiftUI

// MARK: - Session card

/// A session invite in the chat. It carries 1–3 time options: the receiver picks one, suggests
/// other times (which sends a new card), or declines. Once agreed, it shows the chosen time.
struct SessionCard: View {
    let session: SessionProposal
    let mine: Bool
    let profileName: String, chatID: String
    /// A change of the person's is on its way to the server: the buttons wait for it.
    var busy = false
    let onPick: (Date) -> Void
    let onDecline: () -> Void
    let onCounter: () -> Void
    var onCancel: () -> Void = {}
    var onSafety: () -> Void = {}

    @State private var selected: Date?
    @State private var confirmCancel = false

    private var canAnswer: Bool { !mine && session.status == .pending }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(alignment: .center) {
                Image(session.sport.symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DS.Palette.night)
                    .frame(width: 48, height: 48)
                    .background(.white, in: .circle)
                    .accessibilityHidden(true)
                Spacer()
                statusPill
            }

            Text(session.displayTitle)
                .font(.display(session.title.isEmpty ? 28 : 24, relativeTo: .title2))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            times

            if let d = session.discovery {
                // You teach when you sent an .iTeach invite, or received a .theyTeach one.
                let youTeach = (d == .iTeach) == mine
                Label(youTeach ? "Discovery: you show \(profileName) the ropes" : "Discovery: \(profileName) shows you the ropes",
                      image: "stars")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DS.Palette.onAccentOnNight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DS.Palette.accentOnNight, in: .capsule)
            }

            if !session.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(session.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.14), in: .capsule)
                    }
                }
            }

            if !session.note.isEmpty {
                Text(session.note)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: DS.Radius.md))
            }

            actions
        }
        .padding(DS.Space.xl)
        .frame(width: 300, alignment: .leading)
        .nightBlock()
        .opacity(session.status == .countered || session.status == .cancelled ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .onAppear { if session.options.count == 1 { selected = session.options.first } }
        .drafftConfirm(isPresented: $confirmCancel, icon: "calendar-minus",
                       title: L("Cancel this session?"),
                       message: L("\(profileName) will be told it's off."),
                       cancelTitle: L("Keep it"),
                       actions: [ConfirmAction(title: L("Cancel session"), kind: .destructive) { onCancel() }])
    }

    // MARK: Times

    @ViewBuilder
    private var times: some View {
        if session.status == .accepted, let chosen = session.chosen {
            timeRow(chosen, state: .agreed)
        } else {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                if session.options.count > 1 {
                    Text(canAnswer ? "Pick the time that works for you" : "\(session.options.count) times offered")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                ForEach(session.options, id: \.self) { d in
                    if canAnswer {
                        Button {
                            Haptics.select()
                            withAnimation(Motion.select) { selected = d }
                        } label: { timeRow(d, state: selected == d ? .selected : .option) }
                        .buttonStyle(PressScaleStyle(scale: 0.98))
                        .accessibilityAddTraits(selected == d ? .isSelected : [])
                    } else {
                        timeRow(d, state: .option)
                    }
                }
            }
        }
    }

    private enum RowState { case option, selected, agreed }

    private func timeRow(_ d: Date, state: RowState) -> some View {
        let on = state != .option
        return HStack(spacing: DS.Space.sm) {
            Image(state == .agreed ? "check" : "calendar")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(on ? DS.Palette.onAccentOnNight : .white)
                .frame(width: 28, height: 28)
                .background(on ? DS.Palette.accentOnNight : .white.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                Text(d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(.app)))
                    .font(.subheadline.weight(.semibold))
                Text(d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app)))
                    .font(.caption)
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            if canAnswer {
                CheckDisc(isOn: state == .selected, ring: .white.opacity(0.35))
            }
        }
        .padding(DS.Space.sm)
        .background(state == .selected ? DS.Palette.selectedOnNight : .white.opacity(0.06),
                    in: .rect(cornerRadius: DS.Radius.md))
        .accessibilityElement(children: .combine)
    }

    // MARK: Status & actions

    @ViewBuilder
    private var statusPill: some View {
        let (text, icon): (String, String) = switch session.status {
        // No name in the pill: a pill stays on one line, and names are never truncated.
        case .pending: (mine ? L("Waiting") : L("New invite"), "hourglass")
        case .accepted: (L("Confirmed"), "check")
        case .declined: (L("Declined"), "close")
        case .countered: (L("Other times suggested"), "undo-left")
        case .cancelled: (L("Cancelled"), "calendar-minus")
        }
        Label(text, image: icon)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(session.status == .accepted ? DS.Palette.night : .white)
            .background(session.status == .accepted ? Color.white : .white.opacity(0.14), in: .capsule)
            .contentTransition(.opacity)
    }

    @ViewBuilder
    private var actions: some View {
        switch session.status {
        case .pending where !mine:
            VStack(spacing: DS.Space.sm) {
                Button {
                    if let selected { onPick(selected) }
                } label: {
                    Text(selected.map(confirmTitle) ?? L("Pick a time above"))
                        .contentTransition(.opacity)
                }
                .buttonStyle(.drafftPrimary)
                .disabled(selected == nil || busy)
                Button { onCounter() } label: {
                    Label("Suggest other times", image: "calendar")
                }
                .buttonStyle(DrafftButtonStyle(kind: .dark))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl).strokeBorder(.white.opacity(0.2)))
                .disabled(busy)
                Button("Not this time") { onDecline() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .buttonStyle(.textLink(fullWidth: true))
                    .disabled(busy)
            }
        case .pending:
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("\(profileName) will pick a time or suggest others.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                cancelButton
            }
        case .accepted:
            VStack(spacing: DS.Space.xs) {
                CalendarButton(session: session, partner: profileName, chatID: chatID)
                Button(action: onSafety) {
                    Label("Meet safely", image: "shield-check")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                cancelButton
            }
        case .countered:
            Text("New times below.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        default:
            EmptyView()
        }
    }

    /// "Confirm Sat 12, 9:00" for the time picked.
    private func confirmTitle(_ d: Date) -> String {
        let day = d.formatted(.dateTime.weekday(.abbreviated).day().locale(.app))
        let time = d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app))
        return L("Confirm \(day), \(time)")
    }

    /// Either person can call off a pending or confirmed session, after a confirmation.
    private var cancelButton: some View {
        Button("Cancel session") { confirmCancel = true }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .buttonStyle(.textLink(fullWidth: true))
            .disabled(busy)
    }
}
