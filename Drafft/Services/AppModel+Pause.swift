import Foundation

/// The pause switch against the server: sent when the person flips it, read back when signing in,
/// and forced on when the server refuses an action because the profile is paused.
extension AppModel {
    /// The person flipped the switch: send it (the server's own state isn't sent back).
    func pauseChanged(from old: Bool) {
        // Resumed: discovery reads the deck again (nothing was read while paused).
        if old, !profilePaused { refreshDiscovery() }
        guard profilePaused != old, !pauseFromServer else { return }
        let paused = profilePaused
        pauseEdits += 1
        let edit = pauseEdits
        Task { await syncPause(paused, edit: edit) }
    }

    /// The server says the profile is paused (or not): shown as is, never sent back. `readAt` is
    /// `pauseEdits` when the read began: a flip made since, or still being saved, wins over it.
    func applyServerPause(_ paused: Bool, readAt edits: Int? = nil) {
        if let edits, edits != pauseEdits || pauseSaves > 0 { return }
        pauseFromServer = true
        profilePaused = paused
        pauseFromServer = false
    }

    /// Sends the switch to the server; if it can't be saved (signed out included), the switch goes
    /// back to the server's state.
    func syncPause(_ paused: Bool, edit: Int) async {
        pauseSaves += 1
        defer { pauseSaves -= 1 }
        do {
            try await Backend.shared.updateMyProfile(["paused": paused])
        } catch {
            // A later flip is on its way: it decides.
            guard edit == pauseEdits else { return }
            Haptics.warning()
            applyServerPause(!paused)
        }
    }

    /// The saved pause, read back when signing in on this device.
    func loadPause() async {
        struct Row: Decodable { let paused: Bool }
        let edits = pauseEdits
        guard let data = try? await Backend.shared.myProfile(select: "paused"),
              let row = try? JSONDecoder().decode([Row].self, from: data).first else { return }
        applyServerPause(row.paused, readAt: edits)
    }
}
