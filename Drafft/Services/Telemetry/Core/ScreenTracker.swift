import Foundation

/// Which screen is on show, for `Telemetry.screen`. The root sets the `base` (welcome, sign-up, the
/// current tab); a pushed screen, a sheet or a cover `enter`s on top while it's on screen and `leave`s
/// when it goes. The newest one still there is the screen on show.
@MainActor
enum ScreenTracker {
    private struct Layer {
        let token: Int
        let screen: Screen
        let properties: TelemetryProperties
    }

    private static var base: Screen?
    private static var baseProperties: TelemetryProperties = [:]
    private static var layers: [Layer] = []
    private static var nextToken = 0

    static func base(_ screen: Screen, _ properties: TelemetryProperties = [:]) {
        base = screen
        baseProperties = properties
        publish()
    }

    /// A screen comes on top. Keep the token for `leave`.
    static func enter(_ screen: Screen, _ properties: TelemetryProperties = [:]) -> Int {
        let token = nextToken
        nextToken += 1
        layers.append(Layer(token: token, screen: screen, properties: properties))
        publish()
        return token
    }

    static func leave(_ token: Int) {
        let before = layers.count
        layers.removeAll { $0.token == token }
        if layers.count != before { publish() }
    }

    static var current: Screen? { layers.last?.screen ?? base }

    /// Where something happens, as a code for an event (`onboarding`, `phone_verification`...).
    static var currentID: String { current?.id ?? "unknown" }

    private static func publish() {
        let top = layers.last
        guard let screen = top?.screen ?? base else { return }
        Telemetry.screen(screen, top?.properties ?? baseProperties)
    }

    /// Unit tests.
    static func reset() {
        base = nil
        baseProperties = [:]
        layers.removeAll()
    }
}
