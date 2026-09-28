import SwiftUI
import UIKit

/// Who liked you (`liked_me`) and your matches (`my_matches`), from the server and kept live by the
/// account's channel (`UserChannel`): `like`, `match` and `match_ended`. Each event only says something
/// changed; the list is read again, so an event missed while offline is caught up on the next read
/// (front, reconnection). The last lists are kept on this iPhone and shown at launch.
extension AppModel {
    /// Likes read at a time: the Likes tab shows them all.
    private static let likesPage = 100

    // MARK: Likes

    /// Everyone waiting for an answer, super likes first. Unchanged if it can't be read.
    func loadLikes() async {
        guard phase == .main, let data = try? await Backend.shared.rpc("liked_me", ["p_limit": Self.likesPage]),
              let likes = try? LikeCard.list(from: data) else { return }
        applyLikes(likes.map(\.card))
        openLocalCache()?.save(data, as: .likes)
    }

    private func applyLikes(_ cards: [ProfileCard]) {
        let hidden = discovery.swiped.union(blocked.map(\.id)).union(matches.map(\.profile.id))
        let fresh = cards.filter { $0.isShowable && !hidden.contains($0.id) }.map { $0.profile(mediaBase: MediaURL.saved) }
        if fresh != likedMe { withAnimation(Motion.snappy) { likedMe = fresh } }
    }

    /// `like` on the channel. A super like also pins them first in the deck: it's read again.
    func likeReceived(superLike: Bool) async {
        await loadLikes()
        if superLike { loadDeck(.refresh) }
    }

    // MARK: Matches

    /// The current matches. The first read of a session only takes them in; a later one that finds a
    /// new match (they liked you back) shows the banner. Unchanged if it can't be read.
    func loadMatches() async {
        guard phase == .main, let data = try? await Backend.shared.rpc("my_matches", [:]),
              let rows = try? MatchRow.list(from: data) else { return }
        applyMatches(rows, announce: discovery.matchesRead)
        discovery.matchesRead = true
        openLocalCache()?.save(data, as: .matches)
    }

    private func applyMatches(_ rows: [MatchRow], announce: Bool) {
        let fresh = rows.map { row in
            Match(id: row.matchId, profile: row.profile.profile(mediaBase: MediaURL.saved),
                  matchedAt: Self.serverDate(row.matchedAt) ?? .now)
        }
        let new = fresh.filter { !discovery.knownMatches.contains($0.id) }
        discovery.knownMatches.formUnion(fresh.map(\.id))
        let ids = Set(fresh.map(\.profile.id))
        // Matches that ended while this device wasn't listening: their chats go too.
        let ended = Set(matches.map(\.profile.id)).subtracting(ids)
        withAnimation(Motion.snappy) {
            matches = fresh
            conversations.removeAll { ended.contains($0.id) }
            // A match is never in the deck or Likes.
            queue.removeAll { ids.contains($0.id) }
            likedMe.removeAll { ids.contains($0.id) }
        }
        ensureConversations()
        // Someone liked you back (your own swipe shows the match screen instead).
        guard announce, let first = new.first(where: { !discovery.swiped.contains($0.profile.id) }),
              matchScreen?.id != first.profile.id else { return }
        Haptics.success()
        if UIApplication.shared.applicationState == .active {
            withAnimation(Motion.bouncy) { banner = MatchBanner(profile: first.profile) }
        }
        // In the background, the server's push says it.
    }

    /// `match_ended` on the channel (an unmatch or a block, either side): the match and its chat go.
    func matchEnded(_ matchID: String) async {
        let id = matchID.lowercased()
        if let ended = matches.first(where: { $0.id == id }) { endLocally(ended) }
        await loadMatches()
    }

    private func endLocally(_ match: Match) {
        withAnimation(Motion.snappy) {
            matches.removeAll { $0.id == match.id }
            conversations.removeAll { $0.id == match.profile.id }
        }
        if openChatID == match.profile.id { openChatID = nil }
        if banner?.profile.id == match.profile.id { banner = nil }
        if matchScreen?.id == match.profile.id { matchScreen = nil }
    }

    /// Ends the match with this person (`unmatch`): gone at once from Chats; put back with the reason if
    /// the server refuses.
    func unmatch(_ profile: Profile) {
        guard let match = matches.first(where: { $0.profile.id == profile.id }) else { return }
        let conversation = conversation(profile.id)
        endLocally(match)
        Task { [self] in
            do {
                _ = try await Backend.shared.rpc("unmatch", ["p_match": match.id])
            } catch where ServerMessage.code(of: error) == "not_found" {
                // Already over (the other person unmatched or blocked meanwhile).
            } catch {
                withAnimation(Motion.snappy) {
                    if !matches.contains(where: { $0.id == match.id }) { matches.insert(match, at: 0) }
                    if let conversation, self.conversation(profile.id) == nil { conversations.insert(conversation, at: 0) }
                }
                Haptics.warning()
                say(error)
            }
        }
    }

    /// Every current match has its chat in Chats (empty until the chat service fills it), with the
    /// match's latest card.
    func ensureConversations() {
        var list = conversations
        for match in matches where !list.contains(where: { $0.id == match.profile.id }) {
            list.append(Conversation(id: match.profile.id, profile: match.profile, messages: [], matchedAt: match.matchedAt))
        }
        for i in list.indices {
            if let match = matches.first(where: { $0.profile.id == list[i].id }) { list[i].profile = match.profile }
        }
        if list != conversations { withAnimation(Motion.snappy) { conversations = list } }
    }

    // MARK: Cache

    /// Likes and matches as this iPhone last saw them (launch), before the server answers.
    func showCachedLikesAndMatches(_ cache: LocalCache) {
        if likedMe.isEmpty, let entry = cache.entry(.likes), let likes = try? LikeCard.list(from: entry.data) {
            applyLikes(likes.map(\.card))
        }
        if matches.isEmpty, let entry = cache.entry(.matches), let rows = try? MatchRow.list(from: entry.data) {
            applyMatches(rows, announce: false)
        }
    }
}
