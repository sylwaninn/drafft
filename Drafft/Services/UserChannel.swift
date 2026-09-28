import Foundation
import Supabase

/// The person's own Realtime topic, `user:<id>` (private): the database broadcasts on it when
/// something of theirs changes. One channel per account, whatever listens:
///
/// - `moderation`: the hold (`AccountModeration`);
/// - `profile`: the profile row changed (another device, the team): read again with its hold,
///   pause and settings (`AppModel.refreshAccount`);
/// - `wallet`: drafft tempo, boosts and super likes (`AppModel.loadWallet`);
/// - `media`: a photo was approved or refused, by the automatic check or by the team
///   (`PhotoModeration`);
/// - `session_revoked`: Auth sessions ended on the server; this device signs out at once if its own is
///   one of them (`AppModel.sessionsRevoked`);
/// - `profile`: the person's own profile changed, on this device or another one, with the columns that
///   changed (`AppModel.profileChanged`: pause, settings, language, card);
/// - `session`: a session of theirs changed; the calendar event added for it follows (`SessionCalendar`).
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
        let profile = channel.broadcastStream(event: "profile")
        let wallet = channel.broadcastStream(event: "wallet")
        let media = channel.broadcastStream(event: "media")
        let revoked = channel.broadcastStream(event: "session_revoked")
        let profile = channel.broadcastStream(event: "profile")
        let session = channel.broadcastStream(event: "session")
        let status = channel.statusChange
        let joined = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in moderation { await app.refreshAccount(force: true) }; return false }
            group.addTask { for await _ in profile { await app.refreshAccount(force: true) }; return false }
            group.addTask { for await _ in wallet { await app.loadWallet() }; return false }
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
                    await SessionCalendar.shared.sessionChanged(id, status: payload["status"]?.stringValue)
                }
                return false
            }
            group.addTask {
                var joined = false
                for await s in status where s == .subscribed {
                    joined = true
                    await app.refreshAccount(force: true)
                    await app.loadWallet()
                    await PurchaseCredit.shared.resume(app)
                    await app.refreshOwnProfile()
                    await SessionCalendar.shared.refresh()
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
