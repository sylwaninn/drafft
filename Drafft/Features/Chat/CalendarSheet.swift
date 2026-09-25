import SwiftUI
import EventKit
import EventKitUI

/// System "New Event" sheet, prefilled with the session. iOS 17+ needs no calendar permission
/// for this: the person reviews and saves it themselves.
struct AddToCalendarSheet: UIViewControllerRepresentable {
    let session: SessionProposal
    let partner: String
    var onDone: (Bool) -> Void

    private static let store = EKEventStore()

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let event = EKEvent(eventStore: Self.store)
        event.title = L("\(session.displayTitle) with \(partner)")
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
        let onDone: (Bool) -> Void
        init(onDone: @escaping (Bool) -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone(action == .saved)
        }
    }
}

/// "Add to calendar" for a confirmed session. Opens the system sheet; once saved, it turns into
/// "In your calendar". Compact: round icon button (Sessions tab card).
struct CalendarButton: View {
    let session: SessionProposal
    let partner: String
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
                AddToCalendarSheet(session: session, partner: partner) { saved in
                    showSheet = false
                    if saved {
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
        showSheet = true
    }
}
