import Foundation

/// The person's own profile follows the server on every device (pause, notification settings, language,
/// card). The database broadcasts `profile` on `user:<id>` with the names of the columns that changed
/// (`UserChannel`); the app reads the account row again in one request (`refreshAccount`, the single
/// source of the row) and shows the server's version, so the latest write wins whichever device made it.
/// The row is also read again on foreground and on each (re)connection of the channel: a broadcast
/// missed while away or offline is caught up.
extension AppModel {
    /// A `profile` event. `fields`: the changed columns (nil for an unknown payload). Whatever changed,
    /// the whole row is read once and applied everywhere it shows.
    func profileChanged(_ fields: Set<String>?) async {
        guard phase == .main else { return }
        if let fields, fields.isEmpty { return }
        await refreshAccount(force: true)
    }
}
