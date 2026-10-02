import Foundation
@preconcurrency import PostHog

/// `Telemetry.Analytics` on PostHog, EU cloud. Only what `AnalyticsEvent` and `Screen` describe, plus
/// PostHog's own app lifecycle events (installed, updated, opened, backgrounded). No autocapture of
/// taps, no session replay, no surveys, no error tracking (Sentry's job): those would record what's
/// on screen, people included.
///
/// Person profiles exist only for identified accounts (`AnalyticsConsent.granted`); anonymous events
/// stay anonymous events.
struct PostHogAnalytics: Telemetry.Analytics {
    func capture(_ name: String, _ properties: [String: TelemetryValue]) {
        PostHogSDK.shared.capture(name, properties: properties.mapValues(\.raw))
    }

    func screen(_ name: String, _ properties: [String: TelemetryValue]) {
        PostHogSDK.shared.screen(name, properties: properties.mapValues(\.raw))
    }

    func identify(_ id: String) {
        PostHogSDK.shared.identify(id)
    }

    func setPersonProperties(_ properties: [String: TelemetryValue]) {
        PostHogSDK.shared.setPersonProperties(userPropertiesToSet: properties.mapValues(\.raw))
    }

    func register(_ key: String, _ value: TelemetryValue) {
        PostHogSDK.shared.register([key: value.raw])
    }

    func reset() {
        PostHogSDK.shared.reset()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { PostHogSDK.shared.optIn() } else { PostHogSDK.shared.optOut() }
    }

    func flush() {
        PostHogSDK.shared.flush()
    }

    /// Nil without a project key (or with a host outside the EU cloud): PostHog stays off. `optedOut`:
    /// the person refused, nothing is sent.
    @MainActor
    static func start(_ config: TelemetryConfig, optedOut: Bool) -> PostHogAnalytics? {
        guard config.hasPostHog else { return nil }
        let options = PostHogConfig(projectToken: config.postHogKey, host: config.postHogHost)
        options.captureApplicationLifecycleEvents = true
        // SwiftUI screens: the app sends its own (`ScreenTracker`), by stable ids.
        options.captureScreenViews = false
        options.captureElementInteractions = false
        options.capturePushNotificationOpened = false
        options.capturePushNotificationSubscriptions = false
        options.sessionReplay = false
        options.surveys = false
        options.errorTrackingConfig.autoCapture = false
        options.personProfiles = .identifiedOnly
        options.optOut = optedOut
        // No feature flags yet: each preload is a billed request. Turn on with the first experiment.
        options.preloadFeatureFlags = false
        options.sendFeatureFlagEvent = false
        options.debug = false
        // Small batches: a session is short and the app may be killed in the background.
        options.flushAt = 10
        options.flushIntervalSeconds = 30
        // On the way out, whatever called capture: the build's environment goes on every event, PostHog's
        // own `$` ones included and whatever the timing (a registered property can miss the first
        // lifecycle events), and the properties whose names are forbidden are dropped. It doesn't look at
        // values (`Telemetry` already did, through `PrivacyGuard.properties`). PostHog's own `$` events
        // carry its device and app properties, nothing of the person's. `@Sendable`: PostHog runs it on the
        // thread that called capture (any, `Telemetry.track` included), so it must not inherit this
        // function's main actor, whose isolation check would crash off the main thread.
        let environment = config.environment
        let privacyGuard: BeforeSendBlock = { @Sendable event in
            event.properties["app_environment"] = environment
            guard !event.event.hasPrefix("$"),
                  event.properties.keys.contains(where: { PrivacyGuard.forbidden.contains($0) }) else { return event }
            event.properties = event.properties.filter { !PrivacyGuard.forbidden.contains($0.key) }
            return event
        }
        options.setBeforeSend(privacyGuard)
        PostHogSDK.shared.setup(options)
        return PostHogAnalytics()
    }
}
