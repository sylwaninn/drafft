import Foundation

/// The person's own profile follows the server on every device (pause, notification settings, language,
/// card). The database broadcasts `profile` on `user:<id>` with the names of the columns that changed
/// (`UserChannel`); the app reads those parts again and shows the server's row, so the latest write wins
/// whichever device made it. Everything is also read again on foreground and on each (re)connection of
/// the channel: a broadcast missed while away or offline is caught up.
extension AppModel {
    /// Columns `NotificationService.loadSettings` reads (the language included).
    private static let settingColumns = Set(NotificationSettings.CodingKeys.allCases.map(\.rawValue))

    /// A `profile` event. `fields`: the changed columns; nil (an unknown payload) reads everything.
    func profileChanged(_ fields: Set<String>?) async {
        guard phase == .main else { return }
        guard let fields else { return await refreshOwnProfile() }
        async let pause: Void = fields.contains("paused") ? loadPause() : ()
        async let settings: Void = fields.isDisjoint(with: Self.settingColumns)
            ? () : NotificationService.shared.loadSettings()
        let card = !fields.subtracting(Self.settingColumns).subtracting(["paused"]).isEmpty
        async let profile: Void = card ? refreshProfile() : ()
        _ = await (pause, settings, profile)
    }

    /// Everything the profile drives, read again: on foreground and when the live channel (re)connects.
    func refreshOwnProfile() async {
        guard phase == .main else { return }
        async let pause: Void = loadPause()
        async let settings: Void = NotificationService.shared.loadSettings()
        async let profile: Void = refreshProfile()
        _ = await (pause, settings, profile)
    }

    /// The card, read again without showing the loading state: the one on screen stays until the new one
    /// is in, and a failure keeps it (the next event, foreground or reconnect reads it again).
    func refreshProfile() async {
        guard profileLoad == .loaded else { return await loadProfile() }
        let session = sessionID
        guard let saved = try? await ProfileSync.load(), session == sessionID else { return }
        me = saved
    }
}
