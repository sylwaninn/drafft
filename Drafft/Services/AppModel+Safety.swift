import SwiftUI

/// Blocking and unblocking: at once on the device, then on the server (`Safety`).
extension AppModel {
    /// Block (a report blocks too): they leave your deck, your likes and your chats, and undo
    /// can't bring them back.
    func block(_ profile: Profile) {
        guard !blocked.contains(where: { $0.id == profile.id }) else { return }
        withAnimation(Motion.snappy) {
            blocked.insert(profile, at: 0)
            queue.removeAll { $0.id == profile.id }
            history.removeAll { $0.profile.id == profile.id }
            conversations.removeAll { $0.id == profile.id }
        }
        pendingOpeners[profile.id] = nil
        if banner?.profile.id == profile.id { banner = nil }
        Task { await Safety.block(profile.id) }
    }

    /// Unblocking puts them back at the end of Discover; the old chat doesn't come back.
    func unblock(_ profile: Profile) {
        withAnimation(Motion.snappy) { blocked.removeAll { $0.id == profile.id } }
        if !queue.contains(where: { $0.id == profile.id }) { queue.append(profile) }
        Task { await Safety.unblock(profile.id) }
    }
}
