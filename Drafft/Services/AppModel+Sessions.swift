import SwiftUI

/// What the chat and the Sessions tab ask of sessions. The rows live on the server and in
/// `SessionStore` (optimistic, live); the chat's own card is only where the session shows.
///
/// A proposal also puts its card in the chat at once (taken back if the server refuses). db-events posts
/// the card in the channel (`session-<id>-proposed`, `drafft.sessionId`), which then replaces it: the chat
/// keeps one card per session id (`ChatService`).
extension AppModel {
    /// Sends an invite in a chat (`chatID` is the match's id).
    func proposeSession(_ proposal: SessionProposal, in chatID: String) {
        Haptics.tap()
        ChatService.shared.showPending(proposal, in: chatID)
        Task {
            guard await !SessionStore.shared.propose(proposal, in: chatID) else { return }
            removeSessionCard(proposal.id, in: chatID)
        }
    }

    /// Other times for an invite: the old card turns to "Other times suggested", the new one follows.
    func counterSession(_ sessionID: UUID, in chatID: String, with proposal: SessionProposal) {
        Haptics.tap()
        ChatService.shared.showPending(proposal, in: chatID)
        Task {
            guard await !SessionStore.shared.counter(sessionID, with: proposal) else { return }
            removeSessionCard(proposal.id, in: chatID)
        }
    }

    /// Accept one of the proposed times, or decline.
    func respondToSession(_ sessionID: UUID, accept: Bool, pick: Date? = nil) {
        if accept { Haptics.success() } else { Haptics.tap() }
        Task { await SessionStore.shared.respond(sessionID, accept: accept, pick: pick) }
    }

    /// Calls a pending or confirmed session off, for both people.
    func cancelSession(_ sessionID: UUID) {
        Haptics.tap()
        Task { await SessionStore.shared.cancel(sessionID) }
    }

    private func removeSessionCard(_ sessionID: UUID, in chatID: String) {
        ChatService.shared.dropPending(sessionID, in: chatID)
    }
}
