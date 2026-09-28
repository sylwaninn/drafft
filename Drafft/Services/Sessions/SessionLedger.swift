import Foundation

/// A `public.sessions` row as the server sends it (`upcoming_sessions`, the session RPCs, a read by id),
/// with the other person when `upcoming_sessions` adds them (`with`).
struct SessionRecord: Equatable, Sendable, Decodable {
    enum Status: String, Sendable, Decodable { case pending, accepted, declined, countered, cancelled }

    /// The other person, as the Sessions tab shows them.
    struct Partner: Equatable, Sendable {
        let id: UUID
        let name: String
        /// Signed link to their first photo (or its poster), when they have one.
        let photo: String?
    }

    var id: UUID
    var matchID: UUID
    var proposerID: UUID
    var sportID: String
    var options: [Date]
    var chosenAt: Date?
    var title: String
    var note: String
    var tags: [String]
    var discovery: String?
    var status: Status
    var replacesID: UUID?
    /// The row's version: a reply older than what's already known never overwrites it.
    var updatedAt: Date
    var partner: Partner?

    /// The agreed time, or the first option while it's still being decided.
    var date: Date { chosenAt ?? options.first ?? .distantPast }

    /// Still ahead, as the Sessions tab counts it (`upcoming_sessions`): pending or accepted, and its time
    /// (the chosen one, or the last option) less than 2 hours ago.
    func isUpcoming(at now: Date) -> Bool {
        guard status == .pending || status == .accepted else { return false }
        let last = chosenAt ?? options.last ?? .distantPast
        return last > now.addingTimeInterval(-2 * 3600)
    }

    init(id: UUID, matchID: UUID, proposerID: UUID, sportID: String, options: [Date], chosenAt: Date? = nil,
         title: String = "", note: String = "", tags: [String] = [], discovery: String? = nil,
         status: Status = .pending, replacesID: UUID? = nil, updatedAt: Date, partner: Partner? = nil) {
        self.id = id
        self.matchID = matchID
        self.proposerID = proposerID
        self.sportID = sportID
        self.options = options
        self.chosenAt = chosenAt
        self.title = title
        self.note = note
        self.tags = tags
        self.discovery = discovery
        self.status = status
        self.replacesID = replacesID
        self.updatedAt = updatedAt
        self.partner = partner
    }

    private enum CodingKeys: String, CodingKey {
        case id, options, title, note, tags, discovery, status
        case matchID = "match_id", proposerID = "proposer_id", sportID = "sport_id", chosenAt = "chosen_at"
        case replacesID = "replaces_id", updatedAt = "updated_at", with
    }

    private struct With: Decodable {
        struct Media: Decodable {
            let url: String?
            let posterUrl: String?
        }
        let id: UUID
        let name: String?
        let photo: Media?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        matchID = try c.decode(UUID.self, forKey: .matchID)
        proposerID = try c.decode(UUID.self, forKey: .proposerID)
        sportID = try c.decode(String.self, forKey: .sportID)
        options = try c.decode([String].self, forKey: .options).map(ServerDate.parse)
        chosenAt = try c.decodeIfPresent(String.self, forKey: .chosenAt).map(ServerDate.parse)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        discovery = try c.decodeIfPresent(String.self, forKey: .discovery)
        status = try c.decode(Status.self, forKey: .status)
        replacesID = try c.decodeIfPresent(UUID.self, forKey: .replacesID)
        updatedAt = try ServerDate.parse(c.decode(String.self, forKey: .updatedAt))
        partner = try c.decodeIfPresent(With.self, forKey: .with).map {
            Partner(id: $0.id, name: $0.name ?? "", photo: $0.photo?.url ?? $0.photo?.posterUrl)
        }
    }
}

/// Postgres timestamps in JSON: ISO 8601 with an offset, with or without fractional seconds (up to
/// microseconds, which `ISO8601DateFormatter` doesn't read: cut to milliseconds first).
enum ServerDate {
    struct Invalid: Error { let text: String }

    static func parse(_ text: String) throws -> Date {
        let trimmed = text.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: trimmed) ?? ISO8601DateFormatter().date(from: trimmed) { return date }
        throw Invalid(text: text)
    }

    /// What the RPCs are sent: UTC, to the second (the options come back exactly as sent).
    static func string(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

/// The sessions this iPhone knows: the server's rows, with the person's own changes still on their way
/// laid over them. The usual optimistic-update pattern (a pending-mutation queue over confirmed state):
///
/// - a change shows at once (`begin`), whatever the network;
/// - once the server answers, the change is dropped and its returned rows merged (`settle`);
/// - if it refuses or can't be reached, the change is dropped alone (`fail`): the screen goes back to the
///   server's state as it is now, including anything that arrived meanwhile, never to a stale snapshot;
/// - rows are merged by version (`updated_at`): an old reply never overwrites a newer Realtime read.
struct SessionLedger: Equatable, Sendable {
    enum Change: Equatable, Sendable {
        case propose(SessionRecord)
        case respond(UUID, accept: Bool, pick: Date?)
        case counter(UUID, SessionRecord)
        case cancel(UUID)
    }

    struct Pending: Equatable, Sendable {
        let token: UUID
        let change: Change
    }

    private(set) var confirmed: [UUID: SessionRecord] = [:]
    private(set) var pending: [Pending] = []

    /// What the screens show: the server's rows with the pending changes applied, in order.
    var visible: [UUID: SessionRecord] {
        var rows = confirmed
        for p in pending {
            switch p.change {
            case .propose(let row):
                rows[row.id] = row
            case let .respond(id, accept, pick):
                guard var row = rows[id], row.status == .pending else { continue }
                row.status = accept ? .accepted : .declined
                row.chosenAt = accept ? (pick ?? row.options.first) : nil
                rows[id] = row
            case let .counter(id, row):
                if var old = rows[id], old.status == .pending {
                    old.status = .countered
                    rows[id] = old
                }
                rows[row.id] = row
            case .cancel(let id):
                guard var row = rows[id], row.status == .pending || row.status == .accepted else { continue }
                row.status = .cancelled
                rows[id] = row
            }
        }
        return rows
    }

    /// Pending and accepted sessions still ahead, soonest first (the Sessions tab).
    func upcoming(at now: Date) -> [SessionRecord] {
        visible.values.filter { $0.isUpcoming(at: now) }.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }

    /// Whether a change on this session is still on its way (its buttons wait).
    func isBusy(_ id: UUID) -> Bool {
        pending.contains { p in
            switch p.change {
            case .propose(let row): row.id == id
            case .respond(let x, _, _), .cancel(let x): x == id
            case let .counter(x, row): x == id || row.id == id
            }
        }
    }

    /// Server rows, merged by version. The other person is kept when a row comes without them.
    mutating func merge(_ rows: [SessionRecord]) {
        for var row in rows {
            if let known = confirmed[row.id] {
                guard row.updatedAt >= known.updatedAt else { continue }
                row.partner = row.partner ?? known.partner
            }
            confirmed[row.id] = row
        }
    }

    /// A session the server no longer returns (its match or an account is gone).
    mutating func remove(_ ids: Set<UUID>) {
        for id in ids { confirmed[id] = nil }
    }

    /// Starts a change: shown at once. Returns its token for `settle` or `fail`.
    @discardableResult
    mutating func begin(_ change: Change, token: UUID = UUID()) -> UUID {
        pending.append(Pending(token: token, change: change))
        return token
    }

    /// The server accepted the change: it's replaced by the rows it returned.
    mutating func settle(_ token: UUID, with rows: [SessionRecord]) {
        pending.removeAll { $0.token == token }
        merge(rows)
    }

    /// The server refused it or couldn't be reached: undone, back to the server's state.
    mutating func fail(_ token: UUID) {
        pending.removeAll { $0.token == token }
    }

    /// Signed out: nothing of this account stays.
    mutating func reset() {
        confirmed = [:]
        pending = []
    }
}
