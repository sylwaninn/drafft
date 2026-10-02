import Foundation
import Observation

/// Sessions, on the server (`public.sessions`), the one source for the Sessions tab and the chat cards.
///
/// - Reads: `upcoming_sessions` for the tab, a read by id for a card the tab doesn't list (declined,
///   countered, cancelled, past). Again on each Realtime `session` event (`UserChannel`), on each
///   (re)connection and on foreground, so a change made while away is never missed.
/// - Writes: `propose_session`, `counter_session`, `respond_session`, `cancel_session`, optimistic
///   (`SessionLedger`): the card changes at once, is put back if the server refuses, and the refusal is
///   said in the app's words (`SessionFailureNotice`).
/// - Around it: the calendar event added for a session follows it (`SessionCalendar`); reminders are the
///   server's pushes (`notify_session_*`), so a cancelled session never leaves one behind on a phone.
///
/// A voluntary pause doesn't stop any of this (only discovery pauses); a hold does, server side
/// (`moderated`).
@MainActor
@Observable
final class SessionStore {
    static let shared = SessionStore()

    private(set) var ledger = SessionLedger()
    /// A proposal's id on this phone → the server's, once it's saved: a card shown before the server
    /// answered keeps following it.
    @ObservationIgnored private var aliases: [UUID: UUID] = [:]
    /// Ids already asked for, so a card on screen doesn't read its row on every redraw.
    @ObservationIgnored private var requested: Set<UUID> = []
    /// The signed-in person (`proposer_id` tells whose invite a card is).
    @ObservationIgnored private(set) var me: UUID?

    // MARK: Reading

    /// A session as it stands now (server row with the person's changes on their way).
    func record(_ id: UUID) -> SessionRecord? {
        let rows = ledger.visible
        return rows[id] ?? aliases[id].flatMap { rows[$0] }
    }

    /// Pending and accepted sessions still ahead, soonest first.
    var upcoming: [SessionRecord] { ledger.upcoming(at: .now) }

    func isBusy(_ id: UUID) -> Bool { ledger.isBusy(aliases[id] ?? id) }

    func isMine(_ row: SessionRecord) -> Bool { row.proposerID == me }

    /// Everything read again: the upcoming list, then the other sessions this phone shows, by id.
    /// Only a successful read changes anything.
    func refresh() async {
        guard let me = await Backend.shared.userID else { return }
        self.me = me
        guard let rows = await read({ try await Backend.shared.rpc("upcoming_sessions", [:]) }) else { return }
        let returned = Set(rows.map(\.id))
        ledger.merge(rows)
        // Listed before and not now: closed since (cancelled, declined, passed) or gone with its match.
        let others = ledger.confirmed.keys.filter { !returned.contains($0) }
        await load(Set(others), dropMissing: true)
        await SessionCalendar.shared.refresh()
    }

    /// Rows read by id (a chat card, a Realtime event). With `dropMissing`, an id the server no longer
    /// returns is forgotten (its match and chat are gone).
    func load(_ ids: Set<UUID>, dropMissing: Bool = false) async {
        guard !ids.isEmpty else { return }
        if me == nil { me = await Backend.shared.userID }
        let list = ids.map { $0.uuidString.lowercased() }.sorted().joined(separator: ",")
        guard let rows = await read({ try await Backend.shared.select("sessions?id=in.(\(list))&select=*") }) else { return }
        ledger.merge(rows)
        if dropMissing { ledger.remove(ids.subtracting(rows.map(\.id))) }
    }

    /// A card on screen whose row isn't known yet: read once.
    func need(_ id: UUID) {
        guard record(id) == nil, !requested.contains(id) else { return }
        requested.insert(id)
        Task { await load([id]) }
    }

    /// The Realtime `session` event: the row (and the one it replaced) read again, then its calendar
    /// event follows.
    func changed(_ id: UUID, replaces: UUID?, status: String?) async {
        await load(Set([id] + (replaces.map { [$0] } ?? [])))
        await SessionCalendar.shared.sessionChanged(id, status: status)
    }

    // MARK: Writing

    /// A new invite in a match (`matchID` is the chat's id). Shown at once as the person's own.
    @discardableResult
    func propose(_ proposal: SessionProposal, in matchID: String) async -> Bool {
        guard let match = UUID(uuidString: matchID), let me = await Backend.shared.userID else {
            SessionFailureNotice.shared.show(nil)
            return false
        }
        self.me = me
        let local = draft(proposal, match: match, proposer: me)
        let token = ledger.begin(.propose(local))
        do {
            let row = try await call("propose_session", ["p_match": matchID.lowercased(), "p_proposal": body(proposal)])
            aliases[local.id] = row.id
            ledger.settle(token, with: [row])
            return true
        } catch {
            fail(token, error, action: "propose")
            return false
        }
    }

    /// Accept with one of the options, or decline.
    @discardableResult
    func respond(_ id: UUID, accept: Bool, pick: Date?) async -> Bool {
        let id = aliases[id] ?? id
        let token = ledger.begin(.respond(id, accept: accept, pick: pick))
        var params: [String: Any] = ["p_session": id.uuidString.lowercased(), "p_accept": accept]
        if accept, let pick { params["p_pick"] = ServerDate.string(pick) }
        do {
            let row = try await call("respond_session", params)
            ledger.settle(token, with: [row])
            await SessionCalendar.shared.sessionChanged(id, status: row.status.rawValue)
            return true
        } catch {
            fail(token, error, action: accept ? "accept" : "decline")
            return false
        }
    }

    /// Other times for an invite: it becomes `countered`, the new one is the person's own.
    @discardableResult
    func counter(_ id: UUID, with proposal: SessionProposal) async -> Bool {
        let id = aliases[id] ?? id
        guard let old = record(id), let me = await Backend.shared.userID else { return false }
        self.me = me
        let local = draft(proposal, match: old.matchID, proposer: me, replaces: id)
        let token = ledger.begin(.counter(id, local))
        do {
            let row = try await call("counter_session", ["p_session": id.uuidString.lowercased(), "p_proposal": body(proposal)])
            aliases[local.id] = row.id
            // Both rows changed in the same transaction: the old one is countered, as of the new one.
            var countered = old
            countered.status = .countered
            countered.updatedAt = row.updatedAt
            ledger.settle(token, with: [countered, row])
            await SessionCalendar.shared.sessionChanged(id, status: countered.status.rawValue)
            return true
        } catch {
            fail(token, error, action: "counter")
            return false
        }
    }

    /// Either person calls it off (pending or accepted).
    @discardableResult
    func cancel(_ id: UUID) async -> Bool {
        let id = aliases[id] ?? id
        let token = ledger.begin(.cancel(id))
        do {
            let row = try await call("cancel_session", ["p_session": id.uuidString.lowercased()])
            ledger.settle(token, with: [row])
            await SessionCalendar.shared.sessionChanged(id, status: row.status.rawValue)
            return true
        } catch {
            fail(token, error, action: "cancel")
            return false
        }
    }

    /// Signed out: nothing of this account stays.
    func reset() {
        ledger.reset()
        aliases = [:]
        requested = []
        me = nil
    }

    // MARK: Helpers

    private func call(_ rpc: String, _ params: sending [String: Any]) async throws -> SessionRecord {
        let data = try await Backend.shared.rpc(rpc, params)
        return try JSONDecoder().decode(SessionRecord.self, from: data)
    }

    /// Rows read from the server, or nil when the read fails (nothing changes then).
    private func read(_ request: () async throws -> Data) async -> [SessionRecord]? {
        do {
            let data = try await request()
            return try JSONDecoder().decode([SessionRecord].self, from: data)
        } catch {
            Telemetry.unexpected(error, "sessions", "read")
            return nil
        }
    }

    /// Refused or unreachable: the change is undone and the reason said. A refusal also means this
    /// phone's copy may be behind (answered elsewhere, cancelled by the other person): read again.
    private func fail(_ token: UUID, _ error: Error, action: String) {
        Telemetry.track(.sessionActionFailed(action, reason: Telemetry.reason(error)))
        Telemetry.unexpected(error, "sessions", action)
        ledger.fail(token)
        Haptics.warning()
        SessionFailureNotice.shared.show(error)
        if !(error is URLError) { Task { await refresh() } }
    }

    private func body(_ p: SessionProposal) -> [String: Any] {
        var body: [String: Any] = [
            "sport": p.sport.rawValue,
            "options": p.options.map(ServerDate.string),
            "title": p.title,
            "note": p.note,
            "tags": p.tags
        ]
        if let d = p.discovery { body["discovery"] = d.serverValue }
        return body
    }

    private func draft(_ p: SessionProposal, match: UUID, proposer: UUID, replaces: UUID? = nil) -> SessionRecord {
        SessionRecord(id: p.id, matchID: match, proposerID: proposer, sportID: p.sport.rawValue,
                      options: p.options.sorted(), title: p.title, note: p.note, tags: p.tags,
                      discovery: p.discovery?.serverValue, replacesID: replaces, updatedAt: .now)
    }
}

extension SessionProposal.Discovery {
    /// `public.session_discovery`.
    var serverValue: String { self == .iTeach ? "iTeach" : "theyTeach" }
    init?(server: String?) {
        switch server {
        case "iTeach": self = .iTeach
        case "theyTeach": self = .theyTeach
        default: return nil
        }
    }
}

extension SessionProposal {
    /// A server row as the chat card and the Sessions tab show it.
    init?(_ row: SessionRecord) {
        guard let sport = Sport(rawValue: row.sportID) else { return nil }
        self.init(id: row.id, sport: sport, options: row.options, chosen: row.chosenAt, title: row.title,
                  note: row.note, tags: row.tags, discovery: Discovery(server: row.discovery), status: Status(row.status))
    }
}

extension SessionProposal.Status {
    init(_ status: SessionRecord.Status) {
        self = switch status {
        case .pending: .pending
        case .accepted: .accepted
        case .declined: .declined
        case .countered: .countered
        case .cancelled: .cancelled
        }
    }
}
