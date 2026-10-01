import Foundation
import SwiftUI

/// The pause switch against the server: sent when the person flips it, read back when signing in,
/// and forced on when the server refuses an action because the profile is paused.
extension AppModel {
    /// The person flipped the switch: send it (the server's own state isn't sent back).
    func pauseChanged(from old: Bool) {
        // Resumed by the server (another device, a lifted hold): discovery reads the deck again. A
        // flip on this iPhone does it once saved (`syncPause`).
        if old, !profilePaused, pauseFromServer { refreshDiscovery(.entered) }
        guard profilePaused != old, !pauseFromServer else { return }
        let paused = profilePaused
        pauseEdits += 1
        let edit = pauseEdits
        pauseSave = Task { await syncPause(paused, edit: edit) }
    }

    /// Pauses and waits for the server: nil once it has it, else what to say (the switch is back).
    func pauseNow() async -> String? {
        profilePaused = true
        return await pauseSave?.value
    }

    /// The server says the profile is paused (or not): shown as is, never sent back. `readAt` is
    /// `pauseEdits` when the read began: a flip made since, or still being saved, wins over it.
    func applyServerPause(_ paused: Bool, readAt edits: Int? = nil) {
        if let edits, edits != pauseEdits || pauseSaves > 0 { return }
        pauseFromServer = true
        profilePaused = paused
        pauseFromServer = false
    }

    /// A request was refused because the profile is paused. While a flip is being saved the refusal
    /// may predate it, and the save's own outcome decides.
    func serverRefusedPaused() {
        guard pauseSaves == 0 else { return }
        applyServerPause(true)
    }

    /// Sends the switch to the server; if it can't be saved (signed out included), the switch goes
    /// back to the server's state and a notice says so. Nil once saved, else that notice's text.
    @discardableResult
    func syncPause(_ paused: Bool, edit: Int) async -> String? {
        pauseSaves += 1
        defer { pauseSaves -= 1 }
        do {
            try await Backend.shared.updateMyProfile(["paused": paused])
            // Resumed: discovery reads the deck again (nothing was read while paused). Only once
            // the server has it: asked sooner, it answers "paused" and the pause came back on.
            if !paused, edit == pauseEdits { refreshDiscovery(.entered) }
            return nil
        } catch {
            // A later flip is on its way: it decides.
            guard edit == pauseEdits else { return nil }
            Haptics.warning()
            applyServerPause(!paused)
            let text = if !(error is URLError) {
                ServerMessage.text(for: error) ?? ServerMessage.generic
            } else if paused {
                L("Your profile couldn't be paused. Check your connection and try again.")
            } else {
                L("Your profile couldn't be resumed. Check your connection and try again.")
            }
            withAnimation(Motion.bouncy) { notice = Notice(text: text) }
            return text
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
