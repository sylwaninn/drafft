import Foundation

/// Sessions live in Postgres (`sessions`): proposed, answered and countered through RPCs, read back as rows.
/// The chat's card for a session shows its row, so its status is always the server's.
extension ChatService {
    func loadSessions(matchIDs: [String]) async {
        guard !matchIDs.isEmpty else {
            sessions = [:]
            return
        }
        let ids = matchIDs.joined(separator: ",")
        guard let data = try? await Backend.shared.select(
            "sessions?match_id=in.(\(ids))&select=\(SessionRow.columns)&order=created_at.desc&limit=500"),
              let rows = SessionRow.decode(data) else { return }
        sessions = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func loadSessions(ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        let list = ids.map { $0.uuidString.lowercased() }.joined(separator: ",")
        guard let data = try? await Backend.shared.select("sessions?id=in.(\(list))&select=\(SessionRow.columns)"),
              let rows = SessionRow.decode(data) else { return }
        for row in rows { sessions[row.id] = row }
        // Gone (the match ended since): forgotten.
        for id in ids where !rows.contains(where: { $0.id == id }) { sessions[id] = nil }
    }

    // MARK: Sessions

    func propose(_ p: SessionProposal, in matchID: String) {
        Task {
            do {
                let data = try await Backend.shared.rpc("propose_session", ["p_match": matchID, "p_proposal": Self.json(p)])
                if let row = SessionRow.decodeOne(data) {
                    sessions[row.id] = row
                    publish()
                }
            } catch {
                log.error("propose failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Accept one of the proposed times, or decline. Shown at once; the server's row then stands.
    func respond(to sessionID: UUID, accept: Bool, pick: Date?) {
        guard var row = sessions[sessionID] else { return }
        let before = row
        row.status = accept ? "accepted" : "declined"
        if accept { row.chosenAt = pick ?? row.options.first }
        sessions[sessionID] = row
        publish()
        let pickText = accept ? row.chosenAt.map(ServerDate.string) : nil
        Task {
            await settle(sessionID, before: before) {
                var body: [String: Any] = ["p_session": sessionID.uuidString.lowercased(), "p_accept": accept]
                if let pickText { body["p_pick"] = pickText }
                return try await Backend.shared.rpc("respond_session", body)
            }
        }
    }

    /// Other times instead: the invite is marked as countered and a new one goes out.
    func counter(_ sessionID: UUID, with proposal: SessionProposal) {
        guard var row = sessions[sessionID] else { return }
        let before = row
        row.status = "countered"
        sessions[sessionID] = row
        publish()
        Task {
            await settle(sessionID, before: before) {
                try await Backend.shared.rpc("counter_session",
                                             ["p_session": sessionID.uuidString.lowercased(), "p_proposal": Self.json(proposal)])
            }
        }
    }

    func settle(_ id: UUID, before: SessionRow, _ call: () async throws -> Data) async {
        do {
            let data = try await call()
            if let row = SessionRow.decodeOne(data) { sessions[row.id] = row }
            await loadSessions(ids: [id])
        } catch {
            log.error("session change refused: \(error.localizedDescription, privacy: .public)")
            sessions[id] = before
            Haptics.warning()
            await loadSessions(ids: [id])
        }
        publish()
    }

    static func json(_ p: SessionProposal) -> [String: Any] {
        var out: [String: Any] = [
            "sport": p.sport.rawValue,
            "options": p.options.map(ServerDate.string),
            "title": p.title,
            "note": p.note,
            "tags": p.tags
        ]
        if let d = p.discovery { out["discovery"] = d == .iTeach ? "iTeach" : "theyTeach" }
        return out
    }
}
