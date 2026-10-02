import XCTest

// The same cases as the Android app's TelemetryTest.kt: the rules hold on both platforms.

private final class FakeAnalytics: Telemetry.Analytics, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _events: [(String, [String: TelemetryValue])] = []
    private var sending = true

    var calls: [String] { lock.withLock { _calls } }
    var events: [(String, [String: TelemetryValue])] { lock.withLock { _events } }

    func capture(_ name: String, _ properties: [String: TelemetryValue]) {
        lock.withLock { if sending { _events.append((name, properties)) } }
    }
    func screen(_ name: String, _ properties: [String: TelemetryValue]) { lock.withLock { _calls.append("screen:\(name)") } }
    func identify(_ id: String) { lock.withLock { _calls.append("identify:\(id)") } }
    func setPersonProperties(_ properties: [String: TelemetryValue]) {
        lock.withLock { _calls.append("person:\(properties.keys.sorted())") }
    }
    func register(_ key: String, _ value: TelemetryValue) { lock.withLock { _calls.append("register:\(key)=\(value)") } }
    func reset() { lock.withLock { _calls.append("reset") } }
    func setEnabled(_ enabled: Bool) { lock.withLock { sending = enabled } }
    func flush() {}
}

private final class FakeCrashes: Telemetry.CrashReporter, @unchecked Sendable {
    private let lock = NSLock()
    private var _userID: String?
    private var _captured: [(Error, Telemetry.ErrorReport)] = []
    private var _crumbs: [Telemetry.Breadcrumb] = []
    private var _messages: [String] = []
    private var _logs: [String] = []

    var userID: String? { lock.withLock { _userID } }
    var captured: [(Error, Telemetry.ErrorReport)] { lock.withLock { _captured } }
    var crumbs: [Telemetry.Breadcrumb] { lock.withLock { _crumbs } }
    var messages: [String] { lock.withLock { _messages } }
    var logs: [String] { lock.withLock { _logs } }

    func setUser(_ id: String?) { lock.withLock { _userID = id } }
    func setTag(_ key: String, _ value: String?) {}
    func breadcrumb(_ crumb: Telemetry.Breadcrumb) { lock.withLock { _crumbs.append(crumb) } }
    func capture(_ error: Error, _ report: Telemetry.ErrorReport) { lock.withLock { _captured.append((error, report)) } }
    func message(_ text: String, _ level: Telemetry.Level, _ report: Telemetry.ErrorReport) { lock.withLock { _messages.append(text) } }
    func log(_ level: Telemetry.Level, _ text: String, _ attributes: [String: TelemetryValue]) { lock.withLock { _logs.append(text) } }
    func startSpan(_ operation: String, _ description: String) -> any Telemetry.Span { NoopSpan() }

    private struct NoopSpan: Telemetry.Span {
        func setData(_ key: String, _ value: TelemetryValue) {}
        func finish(ok: Bool) {}
    }
}

/// The backend's refusal, as the app's classifier reads `Backend.BackendError.http`.
private struct HTTPFailure: Error {
    let status: Int
    let message: String
}

private enum StoreFailure: Error { case pending, unconfirmed }

private struct TestClassifier: ErrorClassifier {
    func kind(of error: Error) -> ErrorKind {
        if let basic = ErrorKind.basic(error) { return basic }
        if let http = error as? HTTPFailure { return ErrorKind.http(status: http.status, message: http.message) }
        if let store = error as? StoreFailure { return store == .unconfirmed ? .storeUnconfirmed : .storeDeclined }
        return .unexpected
    }

    func code(of error: Error) -> String? {
        guard let http = error as? HTTPFailure, !http.message.contains(" ") else { return nil }
        return http.message
    }
}

private struct Bug: Error {}

final class TelemetryTests: XCTestCase {
    private var analytics = FakeAnalytics()
    private var crashes = FakeCrashes()
    private let someone = "4f2c0e0a-0000-4000-8000-000000000001"

    override func setUp() {
        super.setUp()
        analytics = FakeAnalytics()
        crashes = FakeCrashes()
        Telemetry.uninstall()
        Telemetry.install(crashes: crashes, analytics: analytics, classifier: TestClassifier())
    }

    override func tearDown() {
        Telemetry.uninstall()
        super.tearDown()
    }

    // MARK: Identity and consent

    func testSentryAlwaysGetsTheAccountPostHogOnlyWithConsent() {
        Telemetry.applyConsent(.unknown)
        Telemetry.signedIn(someone)
        XCTAssertEqual(crashes.userID, someone)
        XCTAssertFalse(analytics.calls.contains { $0.hasPrefix("identify") })

        Telemetry.applyConsent(.granted)
        XCTAssertEqual(analytics.calls.filter { $0.hasPrefix("identify") }, ["identify:\(someone)"])
    }

    func testWithdrawingTheConsentStartsANewAnonymousID() {
        Telemetry.applyConsent(.granted)
        Telemetry.signedIn("a")
        Telemetry.applyConsent(.denied)
        XCTAssertTrue(analytics.calls.contains("reset"))
        Telemetry.track(.loggedOut)
        XCTAssertTrue(analytics.events.isEmpty)
    }

    func testSigningOutResetsTheAnonymousID() {
        Telemetry.applyConsent(.granted)
        Telemetry.signedIn("a")
        Telemetry.signedIn(nil)
        XCTAssertNil(crashes.userID)
        XCTAssertTrue(analytics.calls.contains("reset"))
        // Another account later is identified afresh.
        Telemetry.signedIn("b")
        XCTAssertTrue(analytics.calls.contains("identify:b"))
    }

    func testSuperPropertiesSurviveANewAnonymousID() {
        Telemetry.register("app_environment", "production")
        Telemetry.signedIn("a")
        Telemetry.signedIn(nil)
        let afterReset = analytics.calls.drop { $0 != "reset" }
        XCTAssertTrue(afterReset.contains("register:app_environment=production"), "\(afterReset)")
    }

    func testARefusalStillKeepsBreadcrumbsForCrashReports() {
        Telemetry.applyConsent(.denied)
        Telemetry.track(.matchCreated(.mySwipe))
        XCTAssertTrue(analytics.events.isEmpty)
        XCTAssertTrue(crashes.crumbs.contains { $0.message == "match_created" })
    }

    func testConsentIsKeptOnThePhone() throws {
        let suite = "telemetry-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AnalyticsConsent.load(defaults), .unknown)
        AnalyticsConsent.save(.granted, defaults)
        XCTAssertEqual(AnalyticsConsent.load(defaults), .granted)
    }

    // MARK: Events

    func testEventsCarryEnumsAsCodesAndTheScreen() throws {
        Telemetry.screen(.discover)
        Telemetry.track(.profileSwiped(.superLike, source: .deck, withOpener: true, premium: false, likesLeft: nil, deckSize: 12))
        let (name, props) = try XCTUnwrap(analytics.events.first)
        XCTAssertEqual(analytics.events.count, 1)
        XCTAssertEqual(name, "profile_swiped")
        XCTAssertEqual(props["action"], .string("super_like"))
        XCTAssertEqual(props["source"], .string("deck"))
        XCTAssertEqual(props["screen"], .string("discover"))
        XCTAssertNil(props["likes_left"])
    }

    func testTheSameScreenTwiceIsOneView() {
        Telemetry.screen(.chats)
        Telemetry.screen(.chats)
        XCTAssertEqual(analytics.calls.filter { $0.hasPrefix("screen") }, ["screen:chats"])
    }

    @MainActor
    func testTheNewestScreenOnTopIsTheOneOnShow() {
        ScreenTracker.reset()
        ScreenTracker.base(.chats)
        let chat = ScreenTracker.enter(.chat)
        let profile = ScreenTracker.enter(.profileDetail)
        XCTAssertEqual(ScreenTracker.current, .profileDetail)
        // Popping back: the profile leaves, the chat is on show again.
        ScreenTracker.leave(profile)
        XCTAssertEqual(ScreenTracker.current, .chat)
        ScreenTracker.leave(chat)
        XCTAssertEqual(ScreenTracker.current, .chats)
        XCTAssertEqual(analytics.calls.filter { $0.hasPrefix("screen") },
                       ["screen:chats", "screen:chat", "screen:profile_detail", "screen:chat", "screen:chats"])
        ScreenTracker.reset()
    }

    func testEveryEventPassesThePrivacyGuardUntouched() {
        // Every event of the catalog, with sample values: a forbidden or free-text property fails here.
        let code = "some_code"
        let all: [AnalyticsEvent] = [
            .accountCreated(.email), .signUpFailed(code), .emailConfirmed, .emailCodeResent, .loggedIn(.email),
            .logInFailed(code), .passwordResetRequested, .passwordResetCompleted, .loggedOut, .sessionEnded(code),
            .accountDeleted, .accountDeleteFailed(code), .emailChanged, .passwordChanged, .dataExportRequested,
            .termsAccepted(version: code, during: code), .analyticsConsentChanged(.granted), .accountHeld,
            .onboardingStepViewed(step: code, chapter: code, index: 3, resumed: true),
            .onboardingStepCompleted(step: code, chapter: code, index: 3, skipped: true, seconds: 3),
            .onboardingStepBlocked(step: code, reason: code), .onboardingResumed(step: code, index: 3),
            .onboardingCompleted(photos: 3, sports: 3, prompts: 3, hasVoice: true, hasBio: true, hasIcebreaker: true,
                                 answeredLifestyle: true, notificationsAllowed: true, minutes: 3),
            .onboardingFailed(code), .phoneCodeSent(during: code, resend: true), .phoneCodeFailed(during: code, reason: code),
            .phoneVerified(during: code), .phoneVerificationFailed(during: code, reason: code),
            .deckLoaded(cards: 3, mode: code, exhausted: true, seconds: 1.5), .deckLoadFailed(code), .deckEmptyShown(exhausted: true),
            .profileSwiped(.like, source: .deck, withOpener: true, premium: true, likesLeft: 3, deckSize: 3),
            .swipeRefused(.like, reason: code), .swipeUndone(.like), .dailyLikeLimitReached,
            .profileViewed(source: code, hasVoice: true, photos: 3), .filtersChanged(maxDistanceKm: 3, sports: 3, sharedSportsOnly: true),
            .boostStarted(left: 3), .boostFailed(code), .voiceIntroPlayed(where: code), .icebreakerAnswered,
            .likesViewed(count: 3, premium: true), .matchCreated(.mySwipe), .matchScreenAction(code), .unmatched, .matchEnded,
            .chatOpened(unread: 3, messages: 3), .messageSent(.text, isReply: true, isFirst: true, durationSeconds: 3),
            .messageFailed(.text, reason: code), .messageRetried, .messageReacted(removed: true), .messageDeleted,
            .chatMuted(true), .chatMarkedUnread,
            .sessionProposed(sport: code, options: 3), .sessionCountered(options: 3), .sessionResponded(.accepted),
            .sessionCancelled, .sessionActionFailed(code, reason: code), .sessionAddedToCalendar,
            .paywallViewed(.tempo, fromScreen: .discover), .paywallDismissed(.tempo, purchased: true), .productsLoadFailed,
            .purchaseStarted(.tempo, productID: code), .purchaseCompleted(.tempo, productID: code, currency: code),
            .purchaseCancelled(.tempo, productID: code), .purchaseFailed(.tempo, productID: code, problem: code),
            .purchaseCredited(seconds: 3), .purchasesRestored(found: true), .restoreFailed, .subscriptionManageOpened,
            .profileEdited(fields: ["photos", "bio"]), .profileEditFailed(code), .photoUploadStarted(where: code, retry: true),
            .photoUploadFailed(code), .photoRemoved, .photoModerated(code), .photoReviewRequested,
            .voiceIntroRecorded(seconds: 3, where: code), .profilePaused(true), .selfieVerificationStarted,
            .selfieVerificationSubmitted, .selfieVerificationFailed(code),
            .userBlocked, .userUnblocked, .userReported(code), .reportFailed(code),
            .languageChanged(code, during: code), .permissionRequested(.location, result: .granted, during: code),
            .notificationSettingChanged(code, enabled: true), .pushOpened(code), .pushReceived(code, inForeground: true),
            .legalDocOpened(code), .supportContacted(topic: code, signedIn: true), .shareTapped(code)
        ]
        let names = all.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "two events share a name")
        for event in all {
            XCTAssertNotNil(event.name.range(of: "^[a-z]+(_[a-z]+)*$", options: .regularExpression), event.name)
            let checked = PrivacyGuard.check(event.name, event.properties)
            XCTAssertEqual(checked.problems, [], event.name)
            XCTAssertEqual(Set(checked.safe.keys), Set(event.properties.filter { $0.value != nil }.keys), event.name)
        }
    }

    func testEveryEnumValueIsACode() {
        let values: [String] = AnalyticsEvent.SwipeAction.allCases.map(\.rawValue) + AnalyticsEvent.MessageKind.allCases.map(\.rawValue)
            + AnalyticsEvent.ProductKind.allCases.map(\.rawValue) + AnalyticsEvent.PermissionResult.allCases.map(\.rawValue)
            + AnalyticsEvent.MatchSource.allCases.map(\.rawValue) + Screen.allCases.map(\.rawValue) + ErrorKind.allCases.map(\.rawValue)
        for value in values { XCTAssertTrue(PrivacyGuard.isCode(value), value) }
    }

    func testProductKindFromTheStoreID() {
        XCTAssertEqual(AnalyticsEvent.ProductKind(productID: "so.drafft.app.boost.5"), .boost)
        XCTAssertEqual(AnalyticsEvent.ProductKind(productID: "so.drafft.app.superlike.3"), .superLike)
        XCTAssertEqual(AnalyticsEvent.ProductKind(productID: "so.drafft.app.tempo.monthly"), .tempo)
    }

    // MARK: Privacy

    func testSensitivePropertiesNeverLeave() {
        let out = PrivacyGuard.properties("x", ["gender": "woman", "interested_in": "men", "bio": "hi", "email": "a@b.co", "kind": "text"])
        XCTAssertEqual(out, ["kind": .string("text")])
    }

    func testTypedTextIsDropped() {
        let out = PrivacyGuard.properties("x", ["reason": "Hello there!", "product_id": "so.drafft.app.boost.5", "count": 3])
        XCTAssertEqual(out, ["product_id": .string("so.drafft.app.boost.5"), "count": .int(3)])
        // And the drop itself is a log line, so it shows in Sentry.
        XCTAssertEqual(crashes.logs, ["property dropped: x.reason: value isn't a number, a boolean or a short code"])
    }

    func testCheckNamesTheMistake() {
        let checked = PrivacyGuard.check("profile_edited", ["bio": "x"])
        XCTAssertEqual(checked.problems, ["profile_edited.bio: forbidden property"])
        XCTAssertTrue(checked.safe.isEmpty)
    }

    func testScrubTakesOutWhatIdentifiesSomeone() {
        let text = "maya@example.com +33 6 12 34 56 78 0612345678 Bearer abc.def-123 "
            + "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc 48.8566, 2.3522 profile 4f2c0e0a-0000-4000-8000-000000000001 at 1727000000000"
        let scrubbed = PrivacyGuard.scrub(text)
        for leak in ["maya@", "12 34", "0612345678", "abc.def", "eyJ", "48.8566", "4f2c0e0a"] {
            XCTAssertFalse(scrubbed.contains(leak), "\(leak) in \(scrubbed)")
        }
        XCTAssertTrue(scrubbed.contains("1727000000000"), scrubbed)
        XCTAssertTrue(scrubbed.contains("Bearer [token]"), scrubbed)
    }

    func testPathsLoseTheirQuery() {
        XCTAssertEqual(PrivacyGuard.path("rest/v1/profiles?id=eq.4f2c&select=paused"), "rest/v1/profiles")
    }

    // MARK: Errors

    func testOnlyWhatNeedsAFixIsReported() {
        Telemetry.unexpected(URLError(.notConnectedToInternet), "discover")
        Telemetry.unexpected(CancellationError(), "discover")
        Telemetry.unexpected(HTTPFailure(status: 400, message: "daily_like_limit"), "discover")
        Telemetry.unexpected(HTTPFailure(status: 429, message: "rate"), "discover")
        Telemetry.unexpected(StoreFailure.pending, "purchase")
        // Codes the server meant, even without words in the app, and an expired token.
        Telemetry.unexpected(HTTPFailure(status: 404, message: "not_found"), "matches")
        Telemetry.unexpected(HTTPFailure(status: 401, message: "JWT expired"), "account")
        XCTAssertTrue(crashes.captured.isEmpty)

        Telemetry.unexpected(HTTPFailure(status: 503, message: "upstream"), "discover", "load_deck")
        Telemetry.unexpected(HTTPFailure(status: 400, message: "column x does not exist"), "discover")
        Telemetry.unexpected(Bug(), "chat")
        Telemetry.unexpected(StoreFailure.unconfirmed, "purchase")
        XCTAssertEqual(crashes.captured.map { $0.1.extra["kind"] },
                       [.string("server"), .string("client_contract"), .string("unexpected"), .string("store_unconfirmed")])
        XCTAssertEqual(crashes.captured.first?.1.action, "load_deck")
        // What wasn't reported is still in the breadcrumbs, by kind (cancelled leaves nothing).
        XCTAssertEqual(crashes.crumbs.filter { $0.category == "error" }.count, 6)
    }

    func testReasonIsTheServerCodeOrTheKind() {
        XCTAssertEqual(Telemetry.reason(HTTPFailure(status: 400, message: "daily_like_limit")), "daily_like_limit")
        XCTAssertEqual(Telemetry.reason(URLError(.timedOut)), "offline")
        XCTAssertEqual(Telemetry.reason(HTTPFailure(status: 500, message: "boom happened")), "server")
    }

    func testProblemsAndLogsAreScrubbed() {
        Telemetry.log(.warning, "send failed for maya@example.com")
        XCTAssertEqual(crashes.logs, ["send failed for [email]"])
        Telemetry.problem("purchase credited late", "purchase", extra: ["seconds_to_credit": 900])
        XCTAssertEqual(crashes.messages, ["purchase credited late"])
    }

    func testTraceFinishesTheSpanAndKeepsTheValue() async throws {
        let value = await Telemetry.trace("http.client", "POST rest/v1/rpc/discover") { _ in 42 }
        XCTAssertEqual(value, 42)
        do {
            _ = try await Telemetry.trace("media.upload", "profile photo") { _ -> Int in throw Bug() }
            XCTFail("the error goes through")
        } catch is Bug {}
    }

    // MARK: Config

    func testOnlyEURegionsAreUsed() {
        var config = TelemetryConfig(sentryDSN: "https://abc123@o42.ingest.de.sentry.io/7", postHogKey: "phc_x",
                                     postHogHost: "https://eu.i.posthog.com", environment: "production", version: "1.0", build: "3")
        XCTAssertTrue(config.hasSentry)
        XCTAssertTrue(config.hasPostHog)
        XCTAssertEqual(config.release, "so.drafft.app@1.0+3")
        config.sentryDSN = "https://abc123@o42.ingest.us.sentry.io/7"
        config.postHogHost = "https://us.i.posthog.com"
        XCTAssertFalse(config.hasSentry)
        XCTAssertFalse(config.hasPostHog)
        config.sentryDSN = ""
        config.postHogKey = ""
        XCTAssertFalse(config.hasSentry)
        XCTAssertFalse(config.hasPostHog)
    }

    func testProductionSamplesStagingKeepsEverything() {
        let production = TelemetryConfig(sentryDSN: "", postHogKey: "", postHogHost: "", environment: "production", version: "", build: "")
        var staging = production
        staging.environment = "staging"
        XCTAssertEqual(production.requestSampleRate, 0.02)
        XCTAssertEqual(production.tracesSampleRate, 0.2)
        XCTAssertEqual(staging.requestSampleRate, 1.0)
        XCTAssertEqual(staging.tracesSampleRate, 1.0)
    }
}
