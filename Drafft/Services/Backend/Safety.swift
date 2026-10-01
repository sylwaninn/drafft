import Foundation

/// Reports and blocks, on the server. Profiles from the demo data (not server ids) stay on the device.
enum Safety {
    /// The report reaches the safety team (who may hold the account at once, see reports_events), and
    /// blocks them: `report_user` does both.
    static func report(_ person: Profile, reason: ReportReason, details: String) async throws {
        guard UUID(uuidString: person.id) != nil else { return }
        _ = try await Backend.shared.rpc("report_user", [
            "p_target": person.id,
            "p_reason": reason.rawValue,
            "p_details": String(details.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        ])
    }

    /// `block_user` / `unblock_user`. Both are idempotent: sending one again is harmless.
    static func send(_ action: SafetyOutbox.Action, _ id: String) async throws {
        guard UUID(uuidString: id) != nil else { return }
        _ = try await Backend.shared.rpc(action == .block ? "block_user" : "unblock_user", ["p_target": id])
    }

    /// The server turned it down for good (yourself, someone who doesn't exist): sending it again
    /// can't help. A network error, a server error or a session to refresh can.
    static func isFinal(_ error: Error) -> Bool {
        guard case let Backend.BackendError.http(status, _) = error else { return false }
        return (400..<500).contains(status) && ![401, 408, 429].contains(status)
    }

    /// The people you blocked, as the server has them (`blocked_users`), newest first. Their photo
    /// isn't signed for you any more: the list shows names.
    static func blockedPeople() async throws -> [Profile] {
        struct Row: Decodable { let id: String; let name: String? }
        let data = try await Backend.shared.rpc("blocked_users", [:])
        return try JSONDecoder().decode([Row].self, from: data).map { Profile.blocked(id: $0.id, name: $0.name ?? "") }
    }
}

/// Blocks and unblocks not on the server yet, kept on this iPhone until they are: one made offline
/// still reaches the server, after a relaunch too, and the person stays hidden meanwhile. Per account;
/// the last action on a person wins.
enum SafetyOutbox {
    enum Action: String, Codable { case block, unblock }
    struct Entry: Codable, Equatable { let action: Action; let name: String }

    private static func key(_ user: UUID) -> String { "safety.pending.\(user.uuidString.lowercased())" }

    static func pending(for user: UUID) -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: key(user)) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    static func add(_ entry: Entry, for id: String, user: UUID) {
        var all = pending(for: user)
        all[id] = entry
        save(all, user)
    }

    /// Done (or turned down for good): forgotten, unless another action on them came in meanwhile.
    static func remove(_ entry: Entry, for id: String, user: UUID) {
        var all = pending(for: user)
        guard all[id] == entry else { return }
        all[id] = nil
        save(all, user)
    }

    private static func save(_ all: [String: Entry], _ user: UUID) {
        if all.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(user))
        } else if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key(user))
        }
    }
}

extension Profile {
    /// Someone in your blocked list as the server lists them: an id and a name.
    static func blocked(id: String, name: String) -> Profile {
        Profile(id: id, name: name, age: 18, pronouns: nil, gender: nil, neighborhood: "", distanceKm: 0,
                portrait: "", photos: [], sports: [], voiceIntro: nil, voiceDuration: 0,
                icebreaker: Icebreaker.Kind.twoTruths.blank, favoriteSpot: "", bio: "", goal: "")
    }
}
