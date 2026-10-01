import CoreLocation
import SwiftUI

/// Discover on the server (docs/matching.md in drafft-backend):
///
/// - **Batches** from `discover`: the cards still to swipe and 20 new ones (the server ranks from the top,
///   so it sends both), asked again early enough to arrive before the end at the pace the person swipes
///   (`DeckPace`, at least 10 cards ahead). Each batch is the
///   server's fresh order: the cards on screen stay in place if the server still has them, and any
///   card it no longer returns (paused, blocked, swiped on another device, no longer eligible) goes.
///   The deck is also read again at the front, when the account's channel (re)joins, when the
///   filters or the person's own preferences change (from scratch then), and when a pause ends: no
///   card outlives what the server knows (decision 3.8).
/// - **Stale-while-revalidate**: the last batch is kept on this iPhone (`LocalCache`, `.deck`) and shown
///   at launch while the fresh one loads, only if it's recent (its media links are signed for about an
///   hour) and was read with the same filters.
/// - **Swipes** are optimistic: the card leaves at once, the swipe goes to the server in order (undo
///   undoes the server's last one), and a refusal puts things back as they were, with the server's
///   reason in the person's language. A like the server turns down as `not_eligible` (or a card gone,
///   or already swiped elsewhere) just stays gone, without a message.
extension AppModel {
    /// New cards per read.
    static let deckBatch = DeckPace.batch
    /// The most `discover` returns at once.
    private static let deckMaxRead = 50
    /// Cards on screen (the stack shows 4) that a fresh batch doesn't reorder.
    private static let deckKeep = 4

    // MARK: Loading

    enum DeckLoad { case refresh, restart }

    /// Everything discovery shows, read again (entering the app, back at the front, the channel
    /// rejoined): the deck, who liked you, the matches and the likes left.
    func refreshDiscovery() {
        guard phase == .main else { return }
        loadDeck(.refresh)
        Task { await loadLikes() }
        Task { await loadMatches() }
        Task { await loadLikesLeft() }
    }

    /// The last known deck, likes and matches, shown at once at launch (then revalidated).
    func showCachedDiscovery() {
        guard let cache = openLocalCache() else { return }
        if queue.isEmpty, let entry = cache.entry(.deck), entry.savedAt.timeIntervalSinceNow > -DeckCache.maxAge,
           let saved = DeckCache.decode(entry.data), saved.filters == DeckCache.key(filters) {
            let cards = (try? ProfileCard.list(from: saved.cards)) ?? []
            queue = cards.filter(\.isShowable).map { $0.profile(mediaBase: MediaURL.saved) }
            discovery.raw = DeckCache.rawByID(saved.cards)
        }
        showCachedLikesAndMatches(cache)
    }

    /// Reads a batch. `.restart` drops the deck on screen first (new filters or preferences): a card
    /// that doesn't fit them any more never shows. A `.refresh` while one runs waits for it. Any read
    /// but one asked by a swipe may find new people again (`DiscoveryState.exhausted`).
    func loadDeck(_ mode: DeckLoad, afterSwipe: Bool = false) {
        guard phase == .main, !profilePaused else { return }
        if mode == .refresh, discovery.load != nil { return }
        if !afterSwipe { discovery.exhausted = false }
        discovery.load?.cancel()
        discovery.generation += 1
        let generation = discovery.generation
        if mode == .restart {
            queue = []
            discovery.raw = [:]
            openLocalCache()?.remove(.deck)
        }
        // A refresh behind "no one new" (back at the front, the channel rejoined) keeps that screen:
        // flashing the spinner would replay its entrance for nothing.
        if queue.isEmpty, mode == .restart || deckState != .loaded { deckState = .loading }
        let filters = filters
        // The server sends its fresh order from the top, the cards still here included, and may send the
        // swipes not yet on the server (left out): ask for all of those plus a batch of new ones (50 at most).
        let limit = min(Self.deckMaxRead, queue.count + discovery.pendingSwipes + Self.deckBatch)
        discovery.load = Task { [self] in
            let started = ContinuousClock.now
            let outcome = await fetchDeck(filters, limit: limit)
            guard generation == discovery.generation else { return }
            if case .cards = outcome { discovery.pace.read(took: Self.seconds(ContinuousClock.now - started)) }
            discovery.load = nil
            apply(outcome, filters: filters)
        }
    }

    private enum DeckOutcome {
        case cards(Data)
        case refused(String)
        case failed(Error)
    }

    /// One `discover` call; with no location on file, the location is sent first and it's asked again once.
    private func fetchDeck(_ filters: DiscoverFilters, limit: Int) async -> DeckOutcome {
        for attempt in 0..<2 {
            do {
                return .cards(try await Backend.shared.rpc("discover", ["p_filters": filters.serverFilters, "p_limit": limit]))
            } catch {
                guard let code = ServerMessage.code(of: error) else { return .failed(error) }
                if code == "location_required", attempt == 0, await LocationOnce.send() { continue }
                return .refused(code)
            }
        }
        return .refused("location_required")
    }

    private func apply(_ outcome: DeckOutcome, filters: DiscoverFilters) {
        switch outcome {
        case .cards(let data):
            let cards = ((try? ProfileCard.list(from: data)) ?? []).filter(\.isShowable)
            let hidden = discovery.swiped.union(blocked.map(\.id)).union(matches.map(\.profile.id))
            let fresh = cards.filter { !hidden.contains($0.id) }
            let byID = Dictionary(fresh.map { ($0.id, $0.profile(mediaBase: MediaURL.saved)) }) { a, _ in a }
            let held = Set(queue.map(\.id))
            // Fewer new people than a batch: the pool is running out, swipes stop asking until something else does.
            discovery.exhausted = fresh.filter { !held.contains($0.id) }.count < Self.deckBatch
            let order = DeckMerge.merge(current: queue.map(\.id), fresh: fresh.map(\.id), keep: Self.deckKeep,
                                        exclude: hidden)
            // The fresh copy of each card (new links, a changed profile), in the merged order.
            queue = order.compactMap { byID[$0] }
            discovery.raw = DeckCache.rawByID(data)
            deckState = .loaded
            saveDeck(filters)
        case .refused(let code):
            // Paused or on hold: the lock and the hold screen say so.
            if code == "paused" || code == "moderated" { deckState = .idle; return }
            if queue.isEmpty { deckState = .failed(ServerMessage.text(forCode: code) ?? ServerMessage.generic) }
        case .failed(let error):
            if queue.isEmpty {
                deckState = .failed(ServerMessage.text(for: error, offline: L("Couldn't connect. Check your connection and try again.")))
            }
        }
    }

    /// The deck on screen, for the next launch.
    private func saveDeck(_ filters: DiscoverFilters) {
        guard let data = DeckCache.encode(filters: DeckCache.key(filters), cards: queue.compactMap { discovery.raw[$0.id] })
        else { return }
        openLocalCache()?.save(data, as: .deck)
    }

    /// New filters: a new deck, from scratch.
    func filtersChanged() {
        loadDeck(.restart)
    }

    /// The person's own profile changed (any device): preferences that decide the deck start it again.
    func preferencesChanged(_ fields: Set<String>?) {
        let deciding: Set<String> = ["interested_in", "gender", "birthdate", "sport_ids", "onboarded_at"]
        if fields == nil || !(fields ?? []).isDisjoint(with: deciding) { loadDeck(.restart) }
    }

    // MARK: Swipes

    /// A like, super like or pass on someone from the deck or from Likes. `opener`: the first message
    /// (a super like's note is its text).
    func swipe(_ profile: Profile, liked: Bool, superLike: Bool = false, opener: MessageContent? = nil) {
        guard !profilePaused, !discovery.swiped.contains(profile.id) else { return }
        let deckIndex = queue.firstIndex { $0.id == profile.id }
        let likesIndex = likedMe.firstIndex { $0.id == profile.id }
        guard deckIndex != nil || likesIndex != nil else { return }
        withAnimation(Motion.snappy) {
            queue.removeAll { $0.id == profile.id }
            likedMe.removeAll { $0.id == profile.id }
        }
        discovery.swiped.insert(profile.id)
        history.append(Swiped(profile: profile, liked: liked, superLike: superLike, at: .now, fromLikes: deckIndex == nil))
        if superLike {
            superLikes = max(0, superLikes - 1)
        } else if liked, !isPremium, let left = likesLeft {
            likesLeft = max(0, left - 1)
        }
        saveDeck(filters)
        discovery.pace.swiped(at: Self.seconds(ContinuousClock.now - Self.clockStart))
        // Not when the last read had nothing new to add: no read per swipe at the end of a small pool.
        if queue.count <= discovery.pace.lowWater, !discovery.exhausted { loadDeck(.refresh, afterSwipe: true) }
        // The last card went while the next batch is on its way: that's loading, not "no one new".
        if queue.isEmpty, discovery.load != nil { deckState = .loading }

        let target = profile.id
        discovery.pendingSwipes += 1
        enqueue { [self] in
            defer { discovery.pendingSwipes = max(0, discovery.pendingSwipes - 1) }
            do {
                let data = try await Backend.shared.rpc("swipe", Self.swipeBody(target, liked: liked, superLike: superLike, opener: opener))
                struct Result: Decodable { let matched: Bool; let matchId: String? }
                if let result = try? JSONDecoder().decode(Result.self, from: data), result.matched, let id = result.matchId {
                    matched(profile, matchID: id.lowercased())
                }
            } catch {
                swipeFailed(Swiped(profile: profile, liked: liked, superLike: superLike, at: .now),
                            deckIndex: deckIndex, likesIndex: likesIndex, error: error)
            }
            if liked, !superLike { await loadLikesLeft() }
        }
    }

    /// A monotonic origin for the swipe pace.
    private static let clockStart = ContinuousClock.now

    nonisolated private static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// `swipe`'s parameters. A super like's text is its note (140 characters); any other opener is
    /// the first message.
    nonisolated private static func swipeBody(_ target: String, liked: Bool, superLike: Bool, opener: MessageContent?) -> [String: Any] {
        var body: [String: Any] = ["p_target": target, "p_action": superLike ? "superlike" : liked ? "like" : "pass"]
        guard liked else { return body }
        if superLike, case .text(let note)? = opener {
            body["p_note"] = String(note.prefix(140))
        } else if let json = opener?.opener {
            body["p_opener"] = json
        }
        return body
    }

    /// The swipe made a match: the match moment, the chat, and the matches from the server.
    private func matched(_ profile: Profile, matchID: String) {
        if let i = history.lastIndex(where: { $0.profile.id == profile.id }) { history[i].matched = true }
        discovery.knownMatches.insert(matchID)
        if !matches.contains(where: { $0.id == matchID }) {
            withAnimation(Motion.snappy) { matches.insert(Match(id: matchID, profile: profile, matchedAt: .now), at: 0) }
        }
        ensureConversations()
        Haptics.success()
        matchScreen = profile
        Task { await loadMatches() }
    }

    private func swipeFailed(_ swipe: Swiped, deckIndex: Int?, likesIndex: Int?, error: Error) {
        let (profile, liked, superLike) = (swipe.profile, swipe.liked, swipe.superLike)
        let code = ServerMessage.code(of: error)
        history.removeAll { $0.profile.id == profile.id }
        switch code {
        case "not_eligible", "not_found", "already_swiped":
            // Not available any more (or swiped on another device): it stays gone, quietly.
            return
        default:
            break
        }
        // Put it back as it was.
        discovery.swiped.remove(profile.id)
        withAnimation(Motion.snappy) {
            if let deckIndex, !queue.contains(where: { $0.id == profile.id }) {
                queue.insert(profile, at: min(deckIndex, queue.count))
            }
            if let likesIndex, !likedMe.contains(where: { $0.id == profile.id }) {
                likedMe.insert(profile, at: min(likesIndex, likedMe.count))
            }
        }
        if superLike { superLikes += 1 } else if liked, !isPremium, let left = likesLeft { likesLeft = left + 1 }
        switch code {
        case "daily_like_limit": likesLeft = 0
        case "no_super_likes": superLikes = 0
        default: break
        }
        saveDeck(filters)
        Task { await loadWallet() }
        // Paused or on hold: the lock or the hold screen already says it.
        guard code != "paused", code != "moderated" else { return }
        Haptics.warning()
        say(error)
    }

    /// Brings the last swipe back (the server undoes its last one, within 10 minutes, without a match).
    func undo() {
        guard !profilePaused, canUndo, let last = history.popLast() else { return }
        discovery.swiped.remove(last.profile.id)
        withAnimation(Motion.bouncy) {
            if last.fromLikes {
                likedMe.insert(last.profile, at: 0)
            } else {
                queue.insert(last.profile, at: 0)
            }
        }
        if last.superLike { superLikes += 1 } else if last.liked, !isPremium, let left = likesLeft { likesLeft = left + 1 }
        Haptics.tap()
        enqueue { [self] in
            do {
                _ = try await Backend.shared.rpc("undo_last_swipe", [:])
                saveDeck(filters)
            } catch {
                // The server still has the swipe: the card goes again.
                discovery.swiped.insert(last.profile.id)
                withAnimation(Motion.snappy) {
                    queue.removeAll { $0.id == last.profile.id }
                    likedMe.removeAll { $0.id == last.profile.id }
                }
                let code = ServerMessage.code(of: error)
                if code != "paused", code != "moderated" {
                    Haptics.warning()
                    say(error)
                }
            }
            await loadWallet()
            if last.liked, !last.superLike { await loadLikesLeft() }
        }
    }

    /// Swipes and undos reach the server one after the other, in the order they were made.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = discovery.chain
        let session = sessionID
        discovery.chain = Task { [self] in
            await previous?.value
            guard session == sessionID else { return }
            await work()
        }
    }

    /// A refusal or failure, above the tabs, in the person's language.
    func say(_ error: Error) {
        let text = ServerMessage.text(for: error, offline: L("Couldn't connect. Check your connection and try again."))
        withAnimation(Motion.bouncy) { notice = Notice(text: text) }
    }

    // MARK: Likes left

    /// Likes left today, from the server (`likes_left`). Unchanged if it can't be read.
    func loadLikesLeft() async {
        struct Row: Decodable { let unlimited: Bool; let left: Int }
        guard phase == .main,
              let data = try? await Backend.shared.rpc("likes_left", [:]),
              let row = try? JSONDecoder().decode(Row.self, from: data) else { return }
        likesLeft = row.unlimited ? nil : row.left
    }

    // MARK: Boost

    /// 30 minutes at the top of decks nearby (`start_boost`). Shown at once; a refusal puts the boost
    /// back and says why. The wallet then says what the server has.
    func startBoost() {
        guard !profilePaused, boosts > 0, !isBoosting() else { return }
        let before = (boosts: boosts, endsAt: boostEndsAt)
        boosts -= 1
        boostEndsAt = .now.addingTimeInterval(Self.boostDuration)
        Haptics.success()
        boostBanner = UUID()
        Task { [self] in
            do {
                let data = try await Backend.shared.rpc("start_boost", [:])
                if let text = try? JSONDecoder().decode(String.self, from: data), let end = Self.serverDate(text) {
                    boostEndsAt = end
                }
            } catch {
                boosts = before.boosts
                boostEndsAt = before.endsAt
                boostBanner = nil
                let code = ServerMessage.code(of: error)
                if code != "paused", code != "moderated" {
                    Haptics.warning()
                    say(error)
                }
            }
            await loadWallet()
        }
    }

    // MARK: Reset

    /// Signed out: nothing of discovery stays.
    func clearDiscovery() {
        discovery.load?.cancel()
        discovery.chain?.cancel()
        discovery = DiscoveryState()
        queue = []
        deckState = .idle
        history = []
        likedMe = []
        matches = []
        likesLoad = .loading
        matchesLoad = .loading
        likesLeft = nil
        notice = nil
    }
}

/// Discovery's bookkeeping, not observed by the screens.
struct DiscoveryState {
    /// The deck read in flight, and which one (a newer one supersedes it).
    var load: Task<Void, Never>?
    var generation = 0
    /// Swipes and undos, one after the other.
    var chain: Task<Void, Never>?
    /// Everyone swiped in this session: never shown again by a batch read before the server had the swipe.
    var swiped: Set<String> = []
    /// The server's bytes of each card on screen, for the local cache.
    var raw: [String: Data] = [:]
    /// Matches already known: a new one from the channel shows the banner.
    var knownMatches: Set<String> = []
    /// Whether the matches were read once (the first read never shows banners).
    var matchesRead = false
    /// How long reads take and how fast the person swipes: when to read the next batch.
    var pace = DeckPace()
    /// Swipes sent but not answered yet.
    var pendingSwipes = 0
    /// The last read brought fewer new people than a batch: swipes don't ask again until another read
    /// (back at the front, the channel rejoined, new filters) does.
    var exhausted = false
}

/// The deck as kept on this iPhone: the filters it was read with and the cards' own bytes.
enum DeckCache {
    /// Media links are signed for at least an hour: an older copy isn't shown.
    static let maxAge: TimeInterval = 45 * 60

    struct Saved { let filters: String; let cards: Data }

    /// The filters as one stable string.
    static func key(_ filters: DiscoverFilters) -> String {
        let data = try? JSONSerialization.data(withJSONObject: filters.serverFilters, options: [.sortedKeys])
        return data.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
    }

    static func encode(filters: String, cards: [Data]) -> Data? {
        let objects = cards.compactMap { try? JSONSerialization.jsonObject(with: $0) }
        return try? JSONSerialization.data(withJSONObject: ["filters": filters, "cards": objects])
    }

    static func decode(_ data: Data) -> Saved? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filters = object["filters"] as? String, let cards = object["cards"],
              let bytes = try? JSONSerialization.data(withJSONObject: cards) else { return nil }
        return Saved(filters: filters, cards: bytes)
    }

    /// Each card's bytes by id, from a list the server sent.
    static func rawByID(_ data: Data) -> [String: Data] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var out: [String: Data] = [:]
        for card in list {
            guard let id = (card["id"] as? String)?.lowercased(),
                  let bytes = try? JSONSerialization.data(withJSONObject: card) else { continue }
            out[id] = bytes
        }
        return out
    }
}

/// The location, once, when the server has none on file (`location_required`): the same blurred,
/// reduced-accuracy area as sign-up, sent with `set_location`.
@MainActor
enum LocationOnce {
    /// Whether a location was sent.
    static func send() async -> Bool {
        guard let c = await Finder().find() else { return false }
        return (try? await Backend.shared.rpc("set_location", ["p_lat": c.latitude, "p_lng": c.longitude])) != nil
    }

    @MainActor
    private final class Finder: NSObject, CLLocationManagerDelegate {
        private let manager = CLLocationManager()
        private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

        func find() async -> CLLocationCoordinate2D? {
            guard [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) else { return nil }
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyReduced
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                manager.requestLocation()
            }
        }

        nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            let c = locations.last.map { LocationPrivacy.blur($0.coordinate) }
            MainActor.assumeIsolated { finish(c) }
        }

        nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            MainActor.assumeIsolated { finish(nil) }
        }

        private func finish(_ c: CLLocationCoordinate2D?) {
            continuation?.resume(returning: c)
            continuation = nil
        }
    }
}
