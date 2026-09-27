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

    static func block(_ id: String) async {
        guard UUID(uuidString: id) != nil else { return }
        _ = try? await Backend.shared.rpc("block_user", ["p_target": id])
    }

    static func unblock(_ id: String) async {
        guard UUID(uuidString: id) != nil else { return }
        _ = try? await Backend.shared.rpc("unblock_user", ["p_target": id])
    }
}
