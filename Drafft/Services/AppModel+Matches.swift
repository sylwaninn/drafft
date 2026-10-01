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

    /// Everyone waiting for an answer, newest first: the one read of `liked_me`. With drafft tempo
    /// the server sends their cards; without, only a blurred list (`blurredLikes`, decision 5.5). Read
    /// again when Likes opens, on a `like` or `wallet` event (drafft tempo starting or ending) and on
    /// each (re)connection, and quietly back at the front once old enough (`refreshDiscovery`).
    /// Unchanged if it can't be read, or if a newer read already landed.
    func loadLikes() async {
        let premium = isPremium
        guard phase == .main else { return }
        let read = startRead(.likes)
        let data: Data
        do { data = try await Backend.shared.rpc("liked_me", ["p_limit": Self.likesPage]) } catch {
            _ = readLanded(read, ok: false)
            guard read.session == sessionID else { return }
            if isPremium == premium { likesFailed(error) }
            return
        }
        guard isPremium == premium else { _ = readLanded(read, ok: false); return }
        if premium {
            let likes = try? LikeCard.list(from: data)
            guard readLanded(read, ok: likes != nil), let likes else { return likesReadDropped(read) }
            if !blurredLikes.isEmpty { blurredLikes = [] }
            applyLikes(likes)
            openLocalCache()?.save(data, as: .likes)
        } else {
            let fresh = await BlurredLike.list(from: data)
            guard readLanded(read, ok: fresh != nil), let fresh else { return likesReadDropped(read) }
            if !likedMe.isEmpty { likedMe = [] }
            applyBlurredLikes(fresh)
        }
        likesLoad = .loaded
    }

    /// A likes read that isn't applied (unreadable, or older than one already shown): a failure only
    /// for this account, and only while nothing was read yet (`likesFailed`).
    private func likesReadDropped(_ read: (read: DiscoveryFreshness.Read, session: Int)) {
        guard read.session == sessionID else { return }
        likesFailed(nil)
    }

    private func applyBlurredLikes(_ fresh: [BlurredLike]) {
        guard fresh != blurredLikes else { return }
        // New links for the same likes (signatures renew on every read): swapped in place, no
        // animation; anything else animates.
        if fresh.count == blurredLikes.count, zip(fresh, blurredLikes).allSatisfy({ $0.sameLike(as: $1) }) {
            blurredLikes = fresh
        } else {
            withAnimation(Motion.snappy) { blurredLikes = fresh }
        }
        Images.prefetch(fresh.compactMap(\.blurURL), points: CGSize(width: 180, height: 240), variant: "blurred")
    }

    /// A read that failed only shows if nothing was read yet: what's on screen stays otherwise.
    private func likesFailed(_ error: Error?) {
        if likesLoad != .loaded { likesLoad = .failed(offline: error.map(ServerMessage.isOffline) ?? false) }
    }

    private func applyLikes(_ likes: [LikeCard]) {
        let hidden = discovery.swiped.union(blocked.map(\.id)).union(matches.map(\.profile.id))
        let shown = likes.filter { $0.card.isShowable && !hidden.contains($0.card.id) }.map { like in
            var profile = like.card.profile(mediaBase: MediaURL.saved)
            profile.likedAt = like.likedAt.flatMap { try? ServerDate.parse($0) }
            return profile
        }
        let fresh = LikeOrder.newestFirst(shown, date: \.likedAt, id: \.id)
        if fresh != likedMe { withAnimation(Motion.snappy) { likedMe = fresh } }
    }

    /// `like` on the channel. A super like also pins them first in the deck: it's read again.
    func likeReceived(superLike: Bool) async {
        await loadLikes()
        if superLike { loadDeck(.refresh) }
    }

    // MARK: Matches

    /// The current matches. The first read of a session only takes them in; a later one that finds a
    /// new match (they liked you back) shows the banner. Unchanged if it can't be read, or if a newer
    /// read already landed.
    func loadMatches() async {
        guard phase == .main else { return }
        let read = startRead(.matches)
        do {
            let data = try await Backend.shared.rpc("my_matches", [:])
            let rows = try MatchRow.list(from: data)
            guard readLanded(read, ok: true) else { return }
            applyMatches(rows, announce: discovery.matchesRead)
            discovery.matchesRead = true
            matchesLoad = .loaded
            openLocalCache()?.save(data, as: .matches)
        } catch {
            _ = readLanded(read, ok: false)
            guard read.session == sessionID else { return }
            if matchesLoad != .loaded { matchesLoad = .failed(offline: ServerMessage.isOffline(error)) }
        }
    }

    private func applyMatches(_ rows: [MatchRow], announce: Bool) {
        let fresh = rows.map { row in
            Match(id: row.matchId, profile: row.profile.profile(mediaBase: MediaURL.saved),
                  matchedAt: Self.serverDate(row.matchedAt) ?? .now)
        }
        let new = fresh.filter { !discovery.knownMatches.contains($0.id) }
        discovery.knownMatches.formUnion(fresh.map(\.id))
        let ids = Set(fresh.map(\.profile.id))
        // Matches that ended while this device wasn't listening: their chats (keyed by match id) go too.
        let ended = Set(matches.map(\.id)).subtracting(fresh.map(\.id))
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
            conversations.removeAll { $0.id == match.id }
        }
        if openChatID == match.id { openChatID = nil }
        if banner?.profile.id == match.profile.id { banner = nil }
        if matchScreen?.id == match.profile.id { matchScreen = nil }
    }

    /// Ends the match with this person (`unmatch`): gone at once from Chats; put back with the reason if
    /// the server refuses.
    func unmatch(_ profile: Profile) {
        guard let match = matches.first(where: { $0.profile.id == profile.id }) else { return }
        endLocally(match)
        Task { [self] in
            do {
                _ = try await Backend.shared.rpc("unmatch", ["p_match": match.id])
            } catch where ServerMessage.code(of: error) == "not_found" {
                // Already over (the other person unmatched or blocked meanwhile).
            } catch {
                withAnimation(Motion.snappy) {
                    if !matches.contains(where: { $0.id == match.id }) { matches.insert(match, at: 0) }
                }
                ensureConversations()
                Haptics.warning()
                say(error)
            }
        }
    }

    /// Every current match has its chat in Chats (`ChatService`: the match's latest card, its Stream
    /// channel once connected). A chat's id is its match's id (the server's, as sessions and pushes use it).
    func ensureConversations() {
        ChatService.shared.app = self
        ChatService.shared.publish()
    }

    // MARK: Cache

    /// Likes and matches as this iPhone last saw them (launch), before the server answers.
    func showCachedLikesAndMatches(_ cache: LocalCache) {
        // Cards are only kept with drafft tempo (a free account's list is blurred, read live).
        if isPremium, likedMe.isEmpty, let entry = cache.entry(.likes), let likes = try? LikeCard.list(from: entry.data) {
            applyLikes(likes)
            likesLoad = .loaded
        }
        if matches.isEmpty, let entry = cache.entry(.matches), let rows = try? MatchRow.list(from: entry.data) {
            applyMatches(rows, announce: false)
            matchesLoad = .loaded
        }
    }
}
