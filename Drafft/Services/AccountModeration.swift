import SwiftUI

/// A hold the drafft team put on the account (`profiles.moderation`, set from the dashboard): the
/// whole app gives way to a screen saying why (`AccountHoldView`), until it's lifted.
enum AccountHold: String, Decodable {
    /// Being checked: the app opens again by itself once it's cleared.
    case review
    /// A selfie is asked, to check the photos are really them. Sending it moves the account to review.
    case selfie
    /// Closed for good: its email and phone number can't sign up again.
    case banned
}

/// The hold against the server: heard live on the person's own Realtime topic (`UserChannel`), and read again when
/// signing in, coming back to the front, reconnecting, or when the server refuses an action with
/// `moderated`. No restart, no pull to refresh.
@MainActor
@Observable
final class AccountModeration {
    static let shared = AccountModeration()

    /// Shown as is by the hold window.
    private(set) var hold: AccountHold?

    /// Reads the account again (the hold is on its profile row, read in one go by
    /// `AppModel.refreshAccount`, which applies it here). A failed read changes nothing (offline:
    /// the last known state stays).
    func load() async {
        guard await Backend.shared.hasSession else { return }
        await refresh?()
    }

    /// Set by the app: reads the account's row and applies it (`AppModel.refreshAccount`).
    @ObservationIgnored var refresh: (@MainActor () async -> Void)?

    func apply(_ new: AccountHold?) {
        guard new != hold else { return }
        if new != nil {
            AudioPlayback.shared.stop()
            Haptics.warning()
        } else {
            Haptics.success()
        }
        withAnimation(Motion.gentle) { hold = new }
    }

    /// Signed out: nothing to hold any more.
    func clear() { hold = nil }
}
