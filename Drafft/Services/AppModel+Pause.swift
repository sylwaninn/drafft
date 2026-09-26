import Foundation

/// The pause switch against the server: sent when the person flips it, read back when signing in,
/// and forced on when the server refuses an action because the profile is paused.
extension AppModel {
    /// The person flipped the switch: send it (the server's own state isn't sent back).
    func pauseChanged(from old: Bool) {
        guard profilePaused != old, !pauseFromServer else { return }
        let paused = profilePaused
        Task { await syncPause(paused) }
    }

    /// The server says the profile is paused (or not): shown as is, never sent back.
    func applyServerPause(_ paused: Bool) {
        pauseFromServer = true
        profilePaused = paused
        pauseFromServer = false
    }

    /// Sends the switch to the server; if it can't be saved, the switch goes back to the server's state.
    func syncPause(_ paused: Bool) async {
        guard await Backend.shared.hasSession else { return }
        do {
            try await Backend.shared.updateMyProfile(["paused": paused])
        } catch {
            Haptics.warning()
            applyServerPause(!paused)
        }
    }

    /// The saved pause, read back when signing in on this device.
    func loadPause() async {
        struct Row: Decodable { let paused: Bool }
        guard let data = try? await Backend.shared.myProfile(select: "paused"),
              let row = try? JSONDecoder().decode([Row].self, from: data).first else { return }
        applyServerPause(row.paused)
    }
}
