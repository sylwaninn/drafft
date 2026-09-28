import Foundation
import Supabase

/// The person's own Realtime topic, `user:<id>` (private): the database broadcasts on it when
/// something of theirs changes. One channel per account, whatever listens:
///
/// - `moderation`: the hold (`AccountModeration`);
/// - `wallet`: drafft tempo, boosts and super likes (`AppModel.loadWallet`).
///
/// A payload only says a change happened: the row is the truth, read again on each event and on
/// each (re)connection, so a change made while the socket was down isn't missed.
@MainActor
enum UserChannel {
    /// While signed in. Ends when the task is cancelled (sign-out).
    static func watch(_ app: AppModel) async {
        guard let id = await Backend.shared.userID else { return }
        let client = Backend.shared.client
        let channel = client.channel("user:\(id.uuidString.lowercased())") { $0.isPrivate = true }
        let moderation = channel.broadcastStream(event: "moderation")
        let wallet = channel.broadcastStream(event: "wallet")
        let status = channel.statusChange
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in moderation { await AccountModeration.shared.load() } }
            group.addTask { for await _ in wallet { await app.loadWallet() } }
            group.addTask {
                for await s in status where s == .subscribed {
                    await AccountModeration.shared.load()
                    await app.loadWallet()
                }
            }
            group.addTask { try? await channel.subscribeWithError() }
        }
        await client.removeChannel(channel)
    }
}
