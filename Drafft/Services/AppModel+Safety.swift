import SwiftUI
import os

/// Blocking and unblocking: at once on the device, then on the server (`Safety`), through an outbox
/// kept on this iPhone (`SafetyOutbox`) until the server has it: never lost to a dropped connection.
extension AppModel {
    /// Block (a report blocks too): they leave your deck, your likes and your chats, and undo
    /// can't bring them back.
    func block(_ profile: Profile) {
        guard !blocked.contains(where: { $0.id == profile.id }) else { return }
        Telemetry.track(.userBlocked)
        hide(profile)
        queueSafety(.block, profile)
    }

    /// Unblocking lets them back into Discover (the server forgets the old swipe; they come with a
    /// next batch); the old chat doesn't come back.
    func unblock(_ profile: Profile) {
        Telemetry.track(.userUnblocked)
        withAnimation(Motion.snappy) { blocked.removeAll { $0.id == profile.id } }
        discovery.swiped.remove(profile.id)
        queueSafety(.unblock, profile)
    }

    /// The blocked list as the server has it, with what this iPhone hasn't sent yet on top: Blocked
    /// people shows it after a relaunch or on another device too. Unchanged if it can't be read.
    func loadBlocked() async {
        let session = sessionID
        guard let user = Backend.shared.client.auth.currentUser?.id,
              let server = try? await Safety.blockedPeople(), session == sessionID else { return }
        let pending = SafetyOutbox.pending(for: user)
        let listedIDs = Set(server.map(\.id))
        let waiting = pending.filter { $0.value.action == .block && !listedIDs.contains($0.key) }
            .map { id, entry in blocked.first { $0.id == id } ?? .blocked(id: id, name: entry.name) }
        let listed = server.filter { pending[$0.id]?.action != .unblock }
            .map { row in blocked.first { $0.id == row.id } ?? row }
        let list = waiting + listed
        for person in list where !blocked.contains(where: { $0.id == person.id }) { hide(person) }
        blocked = list
    }

    /// Sends what this iPhone hasn't sent yet: the last action on each person. A failure the server
    /// may get over (offline, a server error) waits and tries again; `announce` says so once, for an
    /// action just taken. Signed in, at launch and back at the front: whatever was left goes too.
    func sendPendingSafety(announce: Bool = false) async {
        // One send at a time: a block then an unblock reach the server in that order.
        let previous = safetySending
        let task = Task { await previous?.value; await flushSafety(announce: announce) }
        safetySending = task
        await task.value
    }

    private func flushSafety(announce: Bool) async {
        guard let user = Backend.shared.client.auth.currentUser?.id else { return }
        for (id, entry) in SafetyOutbox.pending(for: user) {
            // Signed out (or into another account) meanwhile: the rest waits for this account's sign-in,
            // never sent with someone else's session.
            guard Backend.shared.client.auth.currentUser?.id == user else { return }
            do {
                try await Safety.send(entry.action, id)
                SafetyOutbox.remove(entry, for: id, user: user)
            } catch where Safety.isFinal(error) {
                Self.safetyLog.error("\(entry.action.rawValue) refused: \(String(describing: error))")
                // The entry is dropped for good: a refusal the server explains is a breadcrumb, a
                // contract bug (a 4xx without a code) is reported, once, before it's forgotten.
                Telemetry.unexpected(error, "safety", entry.action.rawValue)
                SafetyOutbox.remove(entry, for: id, user: user)
            } catch {
                Telemetry.unexpected(error, "safety", entry.action.rawValue)
                if announce {
                    let text = entry.action == .block
                        ? L("Couldn't reach drafft. The block goes through as soon as you're back online.")
                        : L("Couldn't reach drafft. The unblock goes through as soon as you're back online.")
                    withAnimation(Motion.bouncy) { notice = Notice(text: text) }
                }
                retrySafety()
                return
            }
        }
        safetyAttempts = 0
    }

    private static let safetyLog = AppLog("safety")

    private func hide(_ profile: Profile) {
        withAnimation(Motion.snappy) {
            blocked.insert(profile, at: 0)
            queue.removeAll { $0.id == profile.id }
            likedMe.removeAll { $0.id == profile.id }
            matches.removeAll { $0.profile.id == profile.id }
            history.removeAll { $0.profile.id == profile.id }
            conversations.removeAll { $0.profile.id == profile.id }
        }
        ChatService.shared.publish()
        if banner?.profile.id == profile.id { banner = nil }
    }

    private func queueSafety(_ action: SafetyOutbox.Action, _ profile: Profile) {
        guard let user = Backend.shared.client.auth.currentUser?.id else { return }
        SafetyOutbox.add(.init(action: action, name: profile.name), for: profile.id, user: user)
        safetyAttempts = 0
        Task { await sendPendingSafety(announce: true) }
    }

    /// Tries again after 10 s, 30 s, 1 min, then every 5 min while the app is open.
    private func retrySafety() {
        safetyRetry?.cancel()
        let delays = [10, 30, 60, 300]
        let delay = delays[min(safetyAttempts, delays.count - 1)]
        safetyAttempts += 1
        let session = sessionID
        safetyRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, session == self.sessionID else { return }
            await self.sendPendingSafety()
        }
    }
}
