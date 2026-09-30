import SwiftUI

/// Where a system permission stands, in the three cases a screen acts on.
enum PermissionStatus: Equatable {
    /// Never asked: the system prompt can still show.
    case notAsked
    case allowed
    /// Refused (or restricted): iOS won't prompt again, only Settings can turn it on.
    case denied
}

/// A system permission the app asks for. Notifications conform today; location, camera, microphone
/// and photos can join the same way. A conformer keeps `permission` current by itself, coming back
/// from Settings included, so screens only read it and never refresh it themselves.
@MainActor
protocol SystemPermission: AnyObject, Observable {
    var permission: PermissionStatus { get }
    /// The system prompt (it shows once in the app's life; afterwards only Settings changes it).
    @discardableResult func requestPermission() async -> Bool
    /// This permission's own page in Settings when iOS has one, the app's page otherwise.
    var settingsURL: URL? { get }
}

/// The action for a permission that isn't on: the system prompt the first time, then Settings once
/// refused (never a dead, disabled button). Shows nothing to do once allowed: the screen puts its own
/// action there. Styled by its container, like any button.
struct PermissionButton<Permission: SystemPermission>: View {
    let permission: Permission
    /// "Turn on notifications", "Allow location"…
    let askTitle: LocalizedStringKey
    let symbol: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        let refused = permission.permission == .denied
        Button {
            if refused {
                if let url = permission.settingsURL { openURL(url) }
            } else {
                Task { await permission.requestPermission() }
            }
        } label: {
            Label(refused ? "Open Settings" : askTitle, image: refused ? "settings" : symbol)
        }
    }
}
