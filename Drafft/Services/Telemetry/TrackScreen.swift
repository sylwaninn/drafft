import SwiftUI

extension View {
    /// Counts `screen` as on show while this view is on screen: put it on a pushed screen, a sheet's
    /// content or a cover's (the tabs and the root are counted by `RootView`). Not while the tabs are
    /// hidden (under the welcome screen, sign-up or a hold). `properties`: codes and numbers only.
    func trackScreen(_ screen: Screen, _ properties: TelemetryProperties = [:]) -> some View {
        modifier(ScreenTracking(screen: screen, properties: properties))
    }

    /// A paywall or a packs sheet on show: `paywall_viewed` with where it was opened from, then
    /// `paywall_dismissed` with whether something was bought, and the screen itself.
    func trackPaywall(_ kind: AnalyticsEvent.ProductKind, screen: Screen = .paywall,
                      purchased: @escaping @MainActor () -> Bool) -> some View {
        modifier(PaywallTracking(kind: kind, screen: screen, purchased: purchased))
    }
}

private struct ScreenTracking: ViewModifier {
    let screen: Screen
    let properties: TelemetryProperties
    @Environment(\.tabsOnScreen) private var tabsOnScreen
    @State private var visible = false
    @State private var token: Int?

    func body(content: Content) -> some View {
        content
            .onAppear { visible = true; update() }
            .onDisappear { visible = false; update() }
            .onChange(of: tabsOnScreen) { update() }
    }

    private func update() {
        let shown = visible && tabsOnScreen
        if shown, token == nil {
            token = ScreenTracker.enter(screen, properties)
        } else if !shown, let token {
            ScreenTracker.leave(token)
            self.token = nil
        }
    }
}

private struct PaywallTracking: ViewModifier {
    let kind: AnalyticsEvent.ProductKind
    let screen: Screen
    let purchased: @MainActor () -> Bool
    @State private var token: Int?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard token == nil else { return }
                // Read before this sheet counts as on show: the screen it was opened from.
                Telemetry.track(.paywallViewed(kind, fromScreen: ScreenTracker.current))
                token = ScreenTracker.enter(screen)
            }
            .onDisappear {
                guard let token else { return }
                ScreenTracker.leave(token)
                self.token = nil
                Telemetry.track(.paywallDismissed(kind, purchased: purchased()))
            }
    }
}
