import Foundation
import Supabase

/// The person's own Realtime topic, `user:<id>` (private): the database broadcasts on it when
/// something of theirs changes. One channel per account, whatever listens:
///
/// - `moderation`: the hold (`AccountModeration`);
/// - `wallet`: drafft tempo, boosts and super likes (`AppModel.loadWallet`), and who liked you, blurred
///   or not (`AppModel.loadLikes`);
/// - `media`: a photo was approved or refused, by the automatic check or by the team
///   (`PhotoModeration`);
/// - `session_revoked`: Auth sessions ended on the server; this device signs out at once if its own is
///   one of them (`AppModel.sessionsRevoked`);
/// - `profile`: the person's own profile changed, on this device, another one or by the team, with the
///   columns that changed: the row is read again with its hold, pause, settings, language and card
///   (`AppModel.profileChanged`, `AppModel.refreshAccount`);
/// - `session`: a session of theirs was proposed, answered, countered or cancelled: its row (and the one
///   it replaced) is read again for the Sessions tab and the chat cards, and the calendar event added for
///   it follows (`SessionStore`, `SessionCalendar`);
/// - `like`: someone liked them (Likes, and the deck for a super like);
/// - `match`, `match_ended`: a match was made or ended, either side (`AppModel.loadMatches`).
///
/// A payload only says a change happened (a photo decision carries its media and status): the row
/// is the truth, read again on each event and on each (re)connection, so a change made while the
/// socket was down isn't missed.
@MainActor
enum UserChannel {
    /// While signed in. A channel that fails to join, is closed by the server or stays down is
    /// replaced, after a pause that grows while it keeps failing. Ends when the task is cancelled
    /// (sign-out).
    static func watch(_ app: AppModel) async {
        guard let id = await Backend.shared.userID else { return }
        let topic = "user:\(id.uuidString.lowercased())"
        var pause = Duration.seconds(2)
        while !Task.isCancelled {
            let joined = await listen(topic: topic, app: app)
            pause = joined ? .seconds(2) : min(pause * 2, .seconds(60))
            try? await Task.sleep(for: pause)
        }
    }

    /// One channel on the topic, until it's gone (true if it was joined at some point) or the task
    /// is cancelled.
    private static func listen(topic: String, app: AppModel) async -> Bool {
        let client = Backend.shared.client
        let channel = client.channel(topic) { $0.isPrivate = true }
        let moderation = channel.broadcastStream(event: "moderation")
        let wallet = channel.broadcastStream(event: "wallet")
        let media = channel.broadcastStream(event: "media")
        let revoked = channel.broadcastStream(event: "session_revoked")
        let profile = channel.broadcastStream(event: "profile")
        let session = channel.broadcastStream(event: "session")
        let discovery = DiscoveryStreams(channel)
        let status = channel.statusChange
        let joined = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in moderation { await app.refreshAccount(force: true) }; return false }
            group.addTask {
                // drafft tempo starting or ending changes what Likes may show.
                for await _ in wallet { await app.loadWallet(); await app.loadLikes() }
                return false
            }
            group.addTask {
                for await message in media {
                    guard let payload = message["payload"]?.objectValue,
                          let mediaID = payload["mediaId"]?.stringValue,
                          let state = payload["status"]?.stringValue else { continue }
                    await PhotoModeration.shared.apply(mediaID: mediaID, status: state)
                }
                return false
            }
            group.addTask {
                for await message in revoked {
                    let ids = message["payload"]?.objectValue?["sessions"]?.arrayValue?.compactMap(\.stringValue) ?? []
                    await app.sessionsRevoked(ids.map { $0.lowercased() })
                }
                return false
            }
            group.addTask {
                for await message in profile {
                    let fields = message["payload"]?.objectValue?["fields"]?.arrayValue?.compactMap(\.stringValue)
                    await app.profileChanged(fields.map(Set.init))
                }
                return false
            }
            group.addTask {
                for await message in session {
                    guard let payload = message["payload"]?.objectValue,
                          let id = payload["sessionId"]?.stringValue.flatMap(UUID.init(uuidString:)) else { continue }
                    await SessionStore.shared.changed(id, replaces: payload["replacesId"]?.stringValue.flatMap(UUID.init(uuidString:)),
                                                      status: payload["status"]?.stringValue)
                }
                return false
            }
            group.addTask { await discovery.follow(app); return false }
            group.addTask {
                var joined = false
                for await s in status where s == .subscribed {
                    joined = true
                    await app.refreshAccount(force: true)
                    await app.loadWallet()
                    await PurchaseCredit.shared.resume(app)
                    await SessionStore.shared.refresh()
                    // Discovery missed nothing while the socket was down.
                    await app.refreshDiscovery()
                }
                return joined
            }
            group.addTask { await stayJoined(channel, client: client) }
            // The first task to end is the join failing or the channel being gone (the streams only
            // end when cancelled): stop the others and tell if it was ever joined.
            _ = await group.next()
            group.cancelAll()
            var joined = false
            for await result in group { joined = joined || result }
            return joined
        }
        await client.removeChannel(channel)
        return joined
    }

    /// `like`, `match` and `match_ended`, subscribed with the others (before the join).
    private struct DiscoveryStreams {
        let like: AsyncStream<JSONObject>
        let match: AsyncStream<JSONObject>
        let ended: AsyncStream<JSONObject>

        init(_ channel: RealtimeChannelV2) {
            like = channel.broadcastStream(event: "like")
            match = channel.broadcastStream(event: "match")
            ended = channel.broadcastStream(event: "match_ended")
        }

        /// Until cancelled: Likes on a like, the matches on a match or an ended one.
        func follow(_ app: AppModel) async {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await message in like {
                        await app.likeReceived(superLike: message["payload"]?.objectValue?["superLike"]?.boolValue ?? false)
                    }
                }
                group.addTask { for await _ in match { await app.loadMatches() } }
                group.addTask {
                    for await message in ended {
                        guard let id = message["payload"]?.objectValue?["matchId"]?.stringValue else { continue }
                        await app.matchEnded(id)
                    }
                }
            }
        }
    }

    /// Joins, then checks the channel is still up: after a reconnect the SDK joins it again by
    /// itself, so only a channel down for a while (closed by the server, rejoin given up, socket not
    /// reconnecting) ends this one. False if it never joined.
    private static func stayJoined(_ channel: RealtimeChannelV2, client: SupabaseClient) async -> Bool {
        guard (try? await channel.subscribeWithError()) != nil else { return false }
        var downSince: ContinuousClock.Instant?
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            let down = channel.status == .unsubscribed || client.realtimeV2.status == .disconnected
            if !down {
                downSince = nil
            } else if let since = downSince, since.duration(to: .now) >= .seconds(15) {
                return true
            } else if downSince == nil {
                downSince = .now
            }
        }
        return true
    }
}
