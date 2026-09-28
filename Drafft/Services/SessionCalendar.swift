import EventKit
import Foundation

/// The calendar events added from "Add to calendar" follow their session: moved when its time or title
/// changes, removed when it's cancelled, declined, replaced by other times, or gone. Each session keeps
/// the link to its event (saved on the iPhone), and only events drafft added are ever changed:
///
/// - an event is found by the identifier saved when it was added (then by its external identifier, which
///   survives a calendar sync), and must still carry the session's `drafft://session/<id>` URL;
/// - a field the person edited in their calendar (the title, the time) is left as they set it: only a
///   value still equal to the one drafft wrote is updated;
/// - an event the person deleted, or that no longer carries the URL, is let go, never recreated.
///
/// Changes come from the person's own changes once the server took them (`SessionStore`), from the
/// Realtime `session` event (`UserChannel`), and from a re-read on foreground and on each reconnection. Following needs full
/// calendar access, asked when adding the event; with add-only access the event is added and not followed;
/// refused or restricted, a banner says so and opens Settings (`CalendarAccessNotice`).
@MainActor
final class SessionCalendar {
    static let shared = SessionCalendar()

    /// What drafft wrote in an event, to know what the person has edited since.
    struct Link: Codable, Equatable {
        var eventID: String
        var externalID: String?
        /// The conversation (sample ones are never looked up on the server).
        var chatID: String
        /// The other person's name, in the title.
        var partner: String
        var title: String
        var start: Date
    }

    /// Where a session stands, for its event.
    enum State {
        case scheduled(start: Date, title: String)
        case gone
    }

    let store = EKEventStore()
    private static let key = "sessionCalendarLinks"
    private(set) var links: [UUID: Link] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([UUID: Link].self, from: data) {
            links = saved
        }
    }

    static func marker(_ session: UUID) -> URL? { URL(string: "drafft://session/\(session.uuidString.lowercased())") }

    private var canFollow: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// What the app may do with the calendar when the person adds a session.
    enum Access {
        /// Full access: the event is added in the app and follows the session.
        case full
        /// Add-only access: the "New Event" sheet still works, the event isn't followed.
        case addOnly
        /// Refused or restricted: the sheet doesn't open, a banner explains it (`CalendarAccessNotice`).
        case refused
    }

    /// Asked before the "New Event" sheet opens: full access is requested the first time.
    func requestAccess() async -> Access {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .full
        case .writeOnly: return .addOnly
        default: return .refused
        }
    }

    /// The person saved the event from the sheet: remembered, with what drafft wrote in it.
    func added(_ event: EKEvent, session: UUID, chatID: String, partner: String) {
        guard let id = event.eventIdentifier, !id.isEmpty else { return }
        links[session] = Link(eventID: id, externalID: event.calendarItemExternalIdentifier, chatID: chatID,
                              partner: partner, title: event.title ?? "", start: event.startDate)
        save()
    }

    // MARK: Following the session

    /// The event's title for a session: "Sunrise run with Maya", like when it was added.
    static func title(_ session: String, partner: String) -> String { L("\(session) with \(partner)") }

    /// A session changed: the Realtime `session` event, or the person's own change once the server took
    /// it (`SessionStore`). A final status removes the event; any other change is read from the server,
    /// which holds the time and title.
    func sessionChanged(_ id: UUID, status: String?) async {
        guard links[id] != nil else { return }
        switch status {
        case "cancelled", "declined", "countered": apply(.gone, to: id)
        default: await refresh(only: [id])
        }
    }

    /// Every followed session read again from the server: on foreground and on reconnect. Only a
    /// successful read changes anything; a session the server no longer returns is gone.
    func refresh(only ids: Set<UUID>? = nil) async {
        let followed = links.filter { ids?.contains($0.key) ?? true }.filter { !MockData.isSample($0.value.chatID) }
        guard canFollow, !followed.isEmpty else { return }
        let list = followed.keys.map { $0.uuidString.lowercased() }.joined(separator: ",")
        guard let data = try? await Backend.shared.select(
            "sessions?id=in.(\(list))&select=id,status,chosen_at,options,title,sport_id"),
            let rows = try? Self.decoder.decode([Row].self, from: data) else { return }
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, link) in followed {
            guard let row = byID[id], row.status == "accepted" || row.status == "pending" else {
                apply(.gone, to: id)
                continue
            }
            guard row.status == "accepted", let start = row.chosenAt ?? row.options.first else { continue }
            let name = row.title.isEmpty ? Sport(rawValue: row.sportID).map { L("\($0.name) session") } : row.title
            guard let name else { continue }
            apply(.scheduled(start: start, title: Self.title(name, partner: link.partner)), to: id)
        }
    }

    /// Nothing follows another account's sessions on this iPhone (the events themselves stay).
    func forgetAll() {
        links = [:]
        save()
    }

    // MARK: Events

    private func apply(_ state: State, to id: UUID) {
        guard var link = links[id] else { return }
        // Without full access nothing can be read or changed: kept for when it's given.
        guard canFollow else { return }
        guard let event = event(for: id, link) else {
            // Deleted by the person, or no longer drafft's: let go.
            links[id] = nil
            save()
            return
        }
        switch state {
        case .gone:
            // Not removed (the store failed): kept, the next refresh tries again.
            guard (try? store.remove(event, span: .thisEvent, commit: true)) != nil else { return }
            links[id] = nil
        case .scheduled(let start, let title):
            var changed = false
            if event.startDate == link.start, start != link.start {
                let length = event.endDate.timeIntervalSince(event.startDate)
                event.startDate = start
                event.endDate = start.addingTimeInterval(length)
                changed = true
            }
            if event.title == link.title, title != link.title, !title.isEmpty {
                event.title = title
                changed = true
            }
            if changed {
                guard (try? store.save(event, span: .thisEvent, commit: true)) != nil else {
                    store.reset()
                    return
                }
            }
            link.start = start
            link.title = title
            links[id] = link
        }
        save()
    }

    /// The linked event, only if it's still the one drafft added for this session.
    private func event(for id: UUID, _ link: Link) -> EKEvent? {
        var found = store.event(withIdentifier: link.eventID)
        if found == nil, let external = link.externalID {
            found = store.calendarItems(withExternalIdentifier: external).compactMap { $0 as? EKEvent }
                .first { $0.url == Self.marker(id) }
        }
        guard let found, found.url == Self.marker(id) else { return nil }
        return found
    }

    private func save() {
        if let data = try? JSONEncoder().encode(links) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    // MARK: Server rows

    private struct Row: Decodable {
        let id: UUID
        let status: String
        let chosenAt: Date?
        let options: [Date]
        let title: String
        let sportID: String

        enum CodingKeys: String, CodingKey {
            case id, status, options, title
            case chosenAt = "chosen_at"
            case sportID = "sport_id"
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = precise.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
        }
        return d
    }()
}
