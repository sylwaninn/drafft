import UIKit

/// Following a tapped notification (`PushRoute`), once the tabs are on screen (MainTabs takes the
/// pending tap from `NotificationService`). Reuses the app's own navigation: `tab`, `openChat`.
extension AppModel {
    /// How long a chat waits for the first read of the matches (a cold launch) before the list is all
    /// that shows.
    static let pushChatWait: Duration = .seconds(8)
    private static let pushLog = AppLog("push")

    /// Follows a tap, the newest one winning: a tap still being followed is cancelled (counted `replaced`).
    func followPush(_ pending: PendingPushRoute) {
        pushFollow?.cancel()
        pushFollow = Task { await follow(pending) }
    }

    private func follow(_ pending: PendingPushRoute) async {
        let route = pending.route
        let outcome = await run(pending)
        let launch = pending.coldStart ? "launched the app" : "app running"
        Self.pushLog.info("Tapped \(route.kind.rawValue) push (\(launch)), to \(route.destination.code): \(outcome.rawValue)")
        Telemetry.track(.pushOpened(route.kind.rawValue, routed: outcome == .opened))
    }

    private func run(_ pending: PendingPushRoute) async -> Outcome {
        let route = pending.route
        if pending.isExpired() { return .expired }
        // Bound to the account that tapped (nil: the session wasn't read yet, the person who signed in).
        let account = Backend.shared.client.auth.currentUser?.id.uuidString
        let session = sessionID
        func stale() -> Bool {
            session != sessionID || (pending.account != nil && pending.account != account)
        }
        if stale() { return .cancelled }
        if route.destination.clearsPresentedScreens {
            // App-level screens through their state, then whatever sheet or cover is still up.
            matchScreen = nil
            banner = nil
            // The terms gate stays: its sheet isn't dismissed; the destination is set under it and shows
            // once the terms are accepted.
            if termsConsent != .required { await PresentedScreens.dismissAll() }
            if Task.isCancelled { return .replaced }
            if stale() { return .cancelled }
        }
        let outcome = await go(to: route.destination)
        // A destination that isn't what the tap was about (no usable chat id, nothing to name) is a fallback.
        return outcome == .opened && route.fallsBack ? .fallback : outcome
    }

    /// Where the tap ended up: its page (`opened`), the list or tab around it (`fallback`: the page couldn't
    /// be found or the payload named none), nowhere (`expired`: it waited too long; `cancelled`: the account
    /// changed or signed out meanwhile; `replaced`: a newer tap took over).
    private enum Outcome: String { case opened, fallback, expired, cancelled, replaced }

    /// A tap that is never followed (replaced by a newer one, expired while waiting, or dropped on sign-out): counted `routed` false.
    nonisolated static func trackSkippedPush(_ pending: PendingPushRoute) {
        Telemetry.track(.pushOpened(pending.route.kind.rawValue, routed: false))
    }

    private func go(to destination: PushRoute.Destination) async -> Outcome {
        switch destination {
        case .chat(let id):
            return await openChatFromPush(id)
        case .chats:
            tab = .chats
        case .likes:
            tab = .likes
            // The like may be newer than the list on screen (its live event missed while away).
            Task { await loadLikes() }
        case .sessions:
            tab = .sessions
        case .discover:
            tab = .discover
        case .photoRefusal(let media):
            return PhotoModeration.shared.openRefusal(mediaID: media) ? .opened : .fallback
        case .current:
            break
        }
        return .opened
    }

    /// The chat list first (its chats, or its spinner while the matches are read), then the chat once
    /// it's there. A match made a moment ago may not be read yet: one fresh read. Still missing (the
    /// match ended, the read failed): the list stays, never an empty chat.
    private func openChatFromPush(_ id: String) async -> Outcome {
        let session = sessionID
        pushChatTarget = id
        defer { if pushChatTarget == id { pushChatTarget = nil } }
        tab = .chats
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.pushChatWait)
        while conversation(id) == nil, matchesLoad == .loading, session == sessionID, !Task.isCancelled,
              clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(150))
        }
        if Task.isCancelled { return .replaced }
        if conversation(id) == nil, session == sessionID { await loadMatches() }
        if Task.isCancelled { return .replaced }
        guard session == sessionID else { return .cancelled }
        guard conversation(id) != nil else { return .fallback }
        openChat(id)
        return .opened
    }
}

/// The sheets and covers over the tabs, closed so a page opened from outside (a tapped notification)
/// is what shows. SwiftUI hands its bindings back as each one goes. The moderation hold, the location
/// gate and the banners live in their own windows and stay.
@MainActor
enum PresentedScreens {
    static func dismissAll() async {
        guard let root = TopOverlayWindow.appWindow?.rootViewController,
              let presented = root.presentedViewController, !presented.isBeingDismissed else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            root.dismiss(animated: true) { done.resume() }
        }
    }
}
