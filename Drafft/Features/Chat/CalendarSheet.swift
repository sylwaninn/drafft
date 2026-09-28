import SwiftUI
import EventKit
import EventKitUI

/// System "New Event" sheet, prefilled with the session: the person reviews and saves it themselves.
/// It needs no calendar permission; with full access (asked first) the saved event is linked to the
/// session and follows it (`SessionCalendar`), through its `drafft://session/<id>` URL.
struct AddToCalendarSheet: UIViewControllerRepresentable {
    let session: SessionProposal
    let partner: String
    /// The saved event, or nil (cancelled).
    var onDone: (EKEvent?) -> Void

    private static var store: EKEventStore { SessionCalendar.shared.store }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let event = EKEvent(eventStore: Self.store)
        event.title = SessionCalendar.title(session.displayTitle, partner: partner)
        event.url = SessionCalendar.marker(session.id)
        event.startDate = session.date
        event.endDate = session.date.addingTimeInterval(90 * 60)
        event.notes = L("\(session.sport.name) session planned on drafft.")
        event.addAlarm(EKAlarm(relativeOffset: -60 * 60))
        let vc = EKEventEditViewController()
        vc.eventStore = Self.store
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: (EKEvent?) -> Void
        init(onDone: @escaping (EKEvent?) -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone(action == .saved ? controller.event : nil)
        }
    }
}

/// "Add to calendar" for a confirmed session. Opens the system sheet; once saved, it turns into
/// "In your calendar". Compact: round icon button (Sessions tab card).
struct CalendarButton: View {
    let session: SessionProposal
    let partner: String
    /// The conversation it belongs to.
    let chatID: String
    var compact = false

    @Environment(AppModel.self) private var app
    @State private var showSheet = false

    private var added: Bool { app.sessionsInCalendar.contains(session.id) }

    var body: some View {
        Group {
            if compact {
                Button { open() } label: {
                    Image(systemName: added ? "calendar.badge.checkmark" : "calendar.badge.plus")
                        .font(.body.weight(.bold))
                        .foregroundStyle(added ? DS.Palette.lime : .white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.14), in: .circle)
                }
                .buttonStyle(PressScaleStyle())
            } else if added {
                Button { open() } label: {
                    Label("In your calendar", systemImage: "calendar.badge.checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Palette.lime)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white.opacity(0.1), in: .rect(cornerRadius: DS.Radius.xl))
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
            } else {
                Button { open() } label: {
                    Label("Add to calendar", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.drafftPrimary)
                .draftTrail(RoundedRectangle(cornerRadius: DS.Radius.xl), step: CGSize(width: -6, height: 0))
                .padding(.leading, 12)
            }
        }
        .accessibilityLabel(added ? "In your calendar. Add again" : "Add to calendar")
        .sheet(isPresented: $showSheet) {
            Group {
                AddToCalendarSheet(session: session, partner: partner) { event in
                    showSheet = false
                    if let event {
                        SessionCalendar.shared.added(event, session: session.id, chatID: chatID, partner: partner)
                        Haptics.success()
                        withAnimation(Motion.snappy) { _ = app.sessionsInCalendar.insert(session.id) }
                    }
                }
                .ignoresSafeArea()
            }
            .sheetSurface()
        }
    }

    private func open() {
        Haptics.tap()
        // Full access first, so the event can follow the session; the sheet opens either way.
        Task {
            _ = await SessionCalendar.shared.requestAccess()
            showSheet = true
        }
    }
}
