import AuthenticationServices
import XCTest

// The same cases as the Android app's TelemetryTest.kt: the rules hold on both platforms.

/// Records every call, even while disabled: what `Telemetry` must not send is its own guard's to stop,
/// not the fake's.
private final class FakeAnalytics: Telemetry.Analytics, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _events: [(String, [String: TelemetryValue])] = []
    private var _enabled = true

    var calls: [String] { lock.withLock { _calls } }
    var events: [(String, [String: TelemetryValue])] { lock.withLock { _events } }
    var enabled: Bool { lock.withLock { _enabled } }

    func capture(_ name: String, _ properties: [String: TelemetryValue]) { lock.withLock { _events.append((name, properties)) } }
    func screen(_ name: String, _ properties: [String: TelemetryValue]) { lock.withLock { _calls.append("screen:\(name)") } }
    func identify(_ id: String) { lock.withLock { _calls.append("identify:\(id)") } }
    func setPersonProperties(_ properties: [String: TelemetryValue]) {
        lock.withLock { _calls.append("person:\(properties.keys.sorted())") }
    }
    func register(_ key: String, _ value: TelemetryValue) { lock.withLock { _calls.append("register:\(key)=\(value)") } }
    func reset() { lock.withLock { _calls.append("reset") } }
    func setEnabled(_ enabled: Bool) { lock.withLock { _enabled = enabled } }
    func flush() {}
}

private final class FakeCrashes: Telemetry.CrashReporter, @unchecked Sendable {
    private let lock = NSLock()
    private var _userID: String?
    private var _captured: [(Error, Telemetry.ErrorReport)] = []
    private var _crumbs: [Telemetry.Breadcrumb] = []
    private var _messages: [String] = []
    private var _reports: [Telemetry.ErrorReport] = []
    private var _logs: [String] = []
    private var _spans: [Telemetry.SpanStatus] = []

    var userID: String? { lock.withLock { _userID } }
    var captured: [(Error, Telemetry.ErrorReport)] { lock.withLock { _captured } }
    var crumbs: [Telemetry.Breadcrumb] { lock.withLock { _crumbs } }
    var messages: [String] { lock.withLock { _messages } }
    var reports: [Telemetry.ErrorReport] { lock.withLock { _reports } }
    var logs: [String] { lock.withLock { _logs } }
    var spans: [Telemetry.SpanStatus] { lock.withLock { _spans } }

    func setUser(_ id: String?) { lock.withLock { _userID = id } }
    func setTag(_ key: String, _ value: String?) {}
    func breadcrumb(_ crumb: Telemetry.Breadcrumb) { lock.withLock { _crumbs.append(crumb) } }
    func capture(_ error: Error, _ report: Telemetry.ErrorReport) { lock.withLock { _captured.append((error, report)) } }
    func message(_ text: String, _ level: Telemetry.Level, _ report: Telemetry.ErrorReport) {
        lock.withLock { _messages.append(text); _reports.append(report) }
    }
    func log(_ level: Telemetry.Level, _ text: String, _ attributes: [String: TelemetryValue]) { lock.withLock { _logs.append(text) } }
    func startSpan(_ operation: String, _ description: String) -> any Telemetry.Span {
        RecordedSpan { status in self.lock.withLock { self._spans.append(status) } }
    }

    private struct RecordedSpan: Telemetry.Span {
        let done: @Sendable (Telemetry.SpanStatus) -> Void
        func setData(_ key: String, _ value: TelemetryValue) {}
        func finish(_ status: Telemetry.SpanStatus) { done(status) }
    }
}

/// The backend's refusal, as the app's classifier reads `Backend.BackendError.http`.
private struct HTTPFailure: Error {
    let status: Int
    let message: String
}

private enum StoreFailure: Error { case pending, unconfirmed }

/// The shapes of the app's own errors, as `AppErrorClassifier` reads them: Supabase Auth's code (or the
/// database's hint), a verification case's name, a store error's name.
private struct AuthFailure: Error {
    let code: String
    var hint: String?
}
private enum VerificationFailure: Error { case tooManyCodes, wrongCode, sendFailed }
private enum NotLinked: Error { case notLinked }

private struct TestClassifier: ErrorClassifier {
    func kind(of error: Error) -> ErrorKind {
        if let basic = ErrorKind.basic(error) { return basic }
        if let http = error as? HTTPFailure { return ErrorKind.http(status: http.status, message: http.message) }
        if let store = error as? StoreFailure { return store == .unconfirmed ? .storeUnconfirmed : .storeDeclined }
        if error is AuthFailure || error is VerificationFailure { return .refused }
        if error is NotLinked { return .offline }
        return .unexpected
    }

    func code(of error: Error) -> String? {
        if let auth = error as? AuthFailure { return auth.hint ?? auth.code }
        if error is VerificationFailure || error is NotLinked { return String(describing: error).snakeCased }
        guard let http = error as? HTTPFailure, !http.message.contains(" ") else { return nil }
        return http.message
    }
}

private struct Bug: Error {}

/// A clock a test moves by hand.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 1_700_000_000)
    var now: Date { lock.withLock { time } }
    func advance(_ seconds: TimeInterval) { lock.withLock { time = time.addingTimeInterval(seconds) } }
}

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
        XCTAssertFalse(analytics.enabled)
        // The fake takes events whatever the switch says: `Telemetry.track` itself must not send one.
        Telemetry.track(.loggedOut)
        XCTAssertTrue(analytics.events.isEmpty)
    }

    func testSigningInAgainAsTheSameAccountIsOneIdentifyAndNoReset() {
        Telemetry.applyConsent(.granted)
        Telemetry.signedIn("a")
        Telemetry.signedIn("a")
        Telemetry.signedIn("a")
        XCTAssertEqual(analytics.calls.filter { $0.hasPrefix("identify") }, ["identify:a"])
        XCTAssertFalse(analytics.calls.contains("reset"))
    }

    func testSwitchingStraightToAnotherAccountResetsThenIdentifies() {
        Telemetry.applyConsent(.granted)
        Telemetry.signedIn("a")
        Telemetry.signedIn("b")
        XCTAssertEqual(analytics.calls.filter { $0 == "reset" || $0.hasPrefix("identify") }, ["identify:a", "reset", "identify:b"])
        XCTAssertEqual(crashes.userID, "b")
    }

    func testRefusingThenAgreeingAgainWhileSignedInIdentifiesAgain() {
        Telemetry.applyConsent(.granted)
        Telemetry.signedIn("a")
        Telemetry.applyConsent(.denied)
        Telemetry.track(.loggedOut)
        XCTAssertTrue(analytics.events.isEmpty)
        Telemetry.applyConsent(.granted)
        XCTAssertTrue(analytics.enabled)
        XCTAssertEqual(analytics.calls.filter { $0 == "reset" || $0.hasPrefix("identify") }, ["identify:a", "reset", "identify:a"])
        Telemetry.track(.loggedOut)
        XCTAssertEqual(analytics.events.map(\.0), ["logged_out"])
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

    func testPersonPropertiesDescribedBeforeIdentifyingAreSentOnceIdentified() {
        // The app describes the account at launch, before the session is read and the consent applied.
        Telemetry.describeAccount(["is_premium": true, "language": "fr"])
        Telemetry.signedIn(someone)
        XCTAssertFalse(analytics.calls.contains { $0.hasPrefix("person") })
        Telemetry.applyConsent(.granted)
        let after = Array(analytics.calls.drop { !$0.hasPrefix("identify") })
        XCTAssertEqual(after, ["identify:\(someone)", "person:[\"is_premium\", \"language\"]"])
        // Described later, while identified: sent as it comes.
        Telemetry.describeAccount(["is_premium": false])
        XCTAssertEqual(analytics.calls.last, "person:[\"is_premium\"]")
    }

    func testPersonPropertiesOfAnotherAccountAreNotSentAfterSigningOut() {
        Telemetry.applyConsent(.granted)
        Telemetry.signedIn("a")
        Telemetry.describeAccount(["language": "fr"])
        Telemetry.signedIn(nil)
        Telemetry.signedIn("b")
        XCTAssertEqual(analytics.calls.filter { $0.hasPrefix("person") }, ["person:[\"language\"]"])
    }

    func testARefusalSendsNoUsageToAnyone() {
        Telemetry.applyConsent(.denied)
        Telemetry.track(.matchCreated(.mySwipe))
        Telemetry.screen(.chats)
        XCTAssertTrue(analytics.events.isEmpty)
        XCTAssertFalse(analytics.calls.contains { $0.hasPrefix("screen") })
        // Nor a product or navigation breadcrumb in Sentry's crash reports.
        XCTAssertFalse(crashes.crumbs.contains { $0.category == "product" || $0.category == "navigation" }, "\(crashes.crumbs)")
        // What the code needs to fix still reaches Sentry, and what led up to it as errors.
        Telemetry.unexpected(Bug(), "chat", "send")
        Telemetry.unexpected(URLError(.timedOut), "chat", "load")
        XCTAssertEqual(crashes.captured.count, 1)
        XCTAssertEqual(crashes.crumbs.filter { $0.category == "error" }.count, 1)
    }

    func testBeforeARefusalUsageIsABreadcrumb() {
        Telemetry.applyConsent(.unknown)
        Telemetry.track(.matchCreated(.mySwipe))
        Telemetry.screen(.chats)
        XCTAssertEqual(crashes.crumbs.filter { $0.category == "product" }.map(\.message), ["match_created"])
        XCTAssertEqual(crashes.crumbs.filter { $0.category == "navigation" }.map(\.message), ["chats"])
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

    func testACancelledFailureIsNotAnEvent() {
        Telemetry.track(.messageFailed(.text, reason: "cancelled"))
        Telemetry.track(.purchaseFailed(.boost, productID: "so.drafft.app.boost.5", problem: "unconfirmed"))
        XCTAssertEqual(analytics.events.map(\.0), ["purchase_failed"])
        // Nor a breadcrumb: the task going away isn't something that happened to the person.
        XCTAssertEqual(crashes.crumbs.map(\.message), ["purchase_failed"])
        // A cancelled error's reason is `cancelled`, which is what the rule above drops.
        XCTAssertEqual(Telemetry.reason(CancellationError()), "cancelled")
        Telemetry.track(.messageFailed(.text, reason: Telemetry.reason(CancellationError())))
        XCTAssertEqual(analytics.events.count, 1)
    }

    func testTheSameScreenTwiceIsOneView() {
        Telemetry.screen(.chats)
        Telemetry.screen(.chats)
        XCTAssertEqual(analytics.calls.filter { $0.hasPrefix("screen") }, ["screen:chats"])
    }

    @MainActor
    func testTheNewestScreenOnTopIsTheOneOnShow() {
        ScreenTracker.reset()
        defer { ScreenTracker.reset() }
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
    }

    @MainActor
    func testLeavingWithATokenThatIsNotThereSendsNothing() {
        ScreenTracker.reset()
        defer { ScreenTracker.reset() }
        ScreenTracker.base(.chats)
        let chat = ScreenTracker.enter(.chat)
        ScreenTracker.leave(chat + 100)
        XCTAssertEqual(ScreenTracker.current, .chat)
        ScreenTracker.leave(chat)
        // The same token twice (a view's disappear after its tab's): the second changes nothing.
        ScreenTracker.leave(chat)
        XCTAssertEqual(analytics.calls.filter { $0.hasPrefix("screen") }, ["screen:chats", "screen:chat", "screen:chats"])
    }

    @MainActor
    func testANewBaseUnderAScreenOnTopSendsNothingUntilItLeaves() {
        ScreenTracker.reset()
        defer { ScreenTracker.reset() }
        ScreenTracker.base(.chats)
        let chat = ScreenTracker.enter(.chat)
        // The tab changed under a pushed screen: the screen on show is still the pushed one.
        ScreenTracker.base(.likes)
        XCTAssertEqual(ScreenTracker.current, .chat)
        XCTAssertEqual(analytics.calls.filter { $0.hasPrefix("screen") }, ["screen:chats", "screen:chat"])
        ScreenTracker.leave(chat)
        XCTAssertEqual(analytics.calls.filter { $0.hasPrefix("screen") }, ["screen:chats", "screen:chat", "screen:likes"])
    }

    @MainActor
    func testResettingTheTrackerForgetsEverything() {
        ScreenTracker.base(.chats, ["tab": "x"])
        _ = ScreenTracker.enter(.chat)
        ScreenTracker.reset()
        XCTAssertNil(ScreenTracker.current)
        XCTAssertEqual(ScreenTracker.currentID, "unknown")
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
            .notificationSettingChanged(code, enabled: true), .pushOpened(code, routed: true), .pushReceived(code, inForeground: true),
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

    func testACodeEndsWhereItEnds() {
        XCTAssertTrue(PrivacyGuard.isCode("daily_like_limit"))
        // A trailing newline is not part of a code (`$` would let it through).
        XCTAssertFalse(PrivacyGuard.isCode("daily_like_limit\n"))
        XCTAssertFalse(PrivacyGuard.properties("x", ["reason": "ok\n"]).keys.contains("reason"))
    }

    func testAnotherPersonsIDOrAPhoneNumberIsNotAValue() {
        // A UUID or a long run of digits passes as a "code" for a name, never as a value.
        XCTAssertTrue(PrivacyGuard.isCode("4f2c0e0a-0000-4000-8000-000000000001"))
        let out = PrivacyGuard.properties("x", [
            "reason": "4f2c0e0a-0000-4000-8000-000000000001", "call": "0612345678", "digits": "1234567",
            "short": "123456", "mixed": "v12345678", "version": "2", "product_id": "so.drafft.app.boost.5"
        ])
        XCTAssertEqual(out, ["short": .string("123456"), "mixed": .string("v12345678"), "version": .string("2"),
                             "product_id": .string("so.drafft.app.boost.5")])
        XCTAssertEqual(PrivacyGuard.check("x", ["ids": ["a_code", "4f2c0e0a-0000-4000-8000-000000000001"]]).problems.count, 1)
        // The server's own codes keep the looser check (`ErrorKind.http`).
        XCTAssertEqual(ErrorKind.http(status: 400, message: "1234567"), .refused)
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
        XCTAssertEqual(crashes.captured.map { $0.1.extra["error_kind"] },
                       [.string("server"), .string("client_contract"), .string("unexpected"), .string("store_unconfirmed")])
        XCTAssertEqual(crashes.captured.first?.1.action, "load_deck")
        // What wasn't reported is still in the breadcrumbs, by kind (cancelled leaves nothing).
        XCTAssertEqual(crashes.crumbs.filter { $0.category == "error" }.count, 6)
    }

    func testHTTPBoundaries() {
        XCTAssertEqual(ErrorKind.http(status: 428, message: "some words here"), .clientContract)
        XCTAssertEqual(ErrorKind.http(status: 429, message: "daily_like_limit"), .rateLimited)
        XCTAssertEqual(ErrorKind.http(status: 499, message: "some words here"), .clientContract)
        XCTAssertEqual(ErrorKind.http(status: 500, message: "not_found"), .server)
        XCTAssertEqual(ErrorKind.http(status: 600, message: ""), .server)
        // A 401 is the session's business, with a code or without.
        XCTAssertEqual(ErrorKind.http(status: 401, message: "not_authenticated"), .signedOut)
        XCTAssertEqual(ErrorKind.http(status: 401, message: ""), .signedOut)
        // Codes are read in lowercase; no message is no code.
        XCTAssertEqual(ErrorKind.http(status: 400, message: "DAILY_LIKE_LIMIT"), .refused)
        XCTAssertEqual(ErrorKind.http(status: 400, message: ""), .clientContract)
        XCTAssertEqual(ErrorKind.http(status: 400, message: "Duplicate key value"), .clientContract)
    }

    func testOnlyTheConnectionIsOffline() {
        for code in [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost,
                     .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed] {
            XCTAssertEqual(ErrorKind.basic(URLError(code)), .offline, "\(code)")
            XCTAssertEqual(ErrorKind.basic(NSError(domain: NSURLErrorDomain, code: code.rawValue)), .offline, "\(code)")
        }
        // A certificate, a bad URL or an unreadable response is a bug (or an attack), not a phone offline.
        for code in [URLError.Code.secureConnectionFailed, .serverCertificateUntrusted, .appTransportSecurityRequiresSecureConnection,
                     .badURL, .unsupportedURL, .cannotParseResponse, .badServerResponse, .unknown] {
            XCTAssertEqual(ErrorKind.basic(URLError(code)), .unexpected, "\(code)")
            XCTAssertEqual(ErrorKind.basic(NSError(domain: NSURLErrorDomain, code: code.rawValue)), .unexpected, "\(code)")
        }
        XCTAssertEqual(BasicErrorClassifier().kind(of: URLError(.serverCertificateUntrusted)), .unexpected)
        XCTAssertNil(ErrorKind.basic(Bug()))
    }

    func testWhatThePersonClosedIsCancelled() {
        XCTAssertEqual(ErrorKind.basic(CancellationError()), .cancelled)
        XCTAssertEqual(ErrorKind.basic(URLError(.cancelled)), .cancelled)
        XCTAssertEqual(ErrorKind.basic(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)), .cancelled)
        XCTAssertEqual(ErrorKind.basic(CocoaError(.userCancelled)), .cancelled)
        XCTAssertEqual(ErrorKind.basic(ASAuthorizationError(.canceled)), .cancelled)
        // Another Sign in with Apple failure isn't the person's choice.
        XCTAssertNil(ErrorKind.basic(ASAuthorizationError(.failed)))
        XCTAssertEqual(Telemetry.reason(URLError(.cancelled)), "cancelled")
        Telemetry.unexpected(URLError(.cancelled), "discover")
        XCTAssertTrue(crashes.crumbs.isEmpty)
    }

    func testTheSameErrorIsReportedOnceEveryFiveMinutes() {
        let clock = Clock()
        Telemetry.install(now: { clock.now })
        for _ in 0..<5 { Telemetry.unexpected(Bug(), "chat", "send") }
        XCTAssertEqual(crashes.captured.count, 1)
        // The others are still steps leading to the next report.
        XCTAssertEqual(crashes.crumbs.filter { $0.category == "error" }.map(\.message), Array(repeating: "chat.send: unexpected", count: 4))
        // Another place, another action or another kind is another problem.
        Telemetry.unexpected(Bug(), "chat", "load")
        Telemetry.unexpected(Bug(), "discover", "send")
        Telemetry.unexpected(HTTPFailure(status: 500, message: "boom"), "chat", "send")
        XCTAssertEqual(crashes.captured.count, 4)
        clock.advance(299)
        Telemetry.unexpected(Bug(), "chat", "send")
        XCTAssertEqual(crashes.captured.count, 4)
        clock.advance(1)
        Telemetry.unexpected(Bug(), "chat", "send")
        XCTAssertEqual(crashes.captured.count, 5)
        // Grouped by where and what, whatever the error says.
        XCTAssertEqual(crashes.captured.first?.1.fingerprint, ["chat", "send", "unexpected"])
        XCTAssertEqual(crashes.captured.last?.1.fingerprint, ["chat", "send", "unexpected"])
    }

    func testProblemsAndWhatIsNotReportedAreNotLimited() {
        for _ in 0..<3 {
            Telemetry.problem("purchase credited late", "purchase")
            Telemetry.unexpected(URLError(.timedOut), "chat", "send")
        }
        XCTAssertEqual(crashes.messages.count, 3)
        XCTAssertEqual(crashes.crumbs.filter { $0.category == "error" }.count, 3)
    }

    func testTheErrorKindDoesNotReplaceTheCallersKind() throws {
        Telemetry.unexpected(Bug(), "chat", "send", extra: ["kind": "voice"])
        let report = try XCTUnwrap(crashes.captured.first?.1)
        XCTAssertEqual(report.extra["kind"], .string("voice"))
        XCTAssertEqual(report.extra["error_kind"], .string("unexpected"))
        XCTAssertEqual(report.tags["error_kind"], "unexpected")
    }

    func testTheCallerCanSayWhatTheClassifierCannot() throws {
        Telemetry.unexpected(Bug(), "purchase", "purchase", kind: .storeUnconfirmed)
        XCTAssertEqual(crashes.captured.first?.1.extra["error_kind"], .string("store_unconfirmed"))
        Telemetry.unexpected(Bug(), "purchase", "restore", kind: .cancelled)
        XCTAssertEqual(crashes.captured.count, 1)
    }

    func testReasonIsTheServerCodeOrTheKind() {
        XCTAssertEqual(Telemetry.reason(HTTPFailure(status: 400, message: "daily_like_limit")), "daily_like_limit")
        XCTAssertEqual(Telemetry.reason(URLError(.timedOut)), "offline")
        XCTAssertEqual(Telemetry.reason(HTTPFailure(status: 500, message: "boom happened")), "server")
    }

    func testReasonOfAuthVerificationAndStoreErrors() {
        // Supabase Auth's code, or the database's hint when it gave one (a banned address is `email_taken`).
        XCTAssertEqual(Telemetry.reason(AuthFailure(code: "invalid_credentials")), "invalid_credentials")
        XCTAssertEqual(Telemetry.reason(AuthFailure(code: "unexpected_failure", hint: "email_taken")), "email_taken")
        // A verification case by its name, snake_case.
        XCTAssertEqual(Telemetry.reason(VerificationFailure.tooManyCodes), "too_many_codes")
        XCTAssertEqual(Telemetry.reason(VerificationFailure.wrongCode), "wrong_code")
        // The store's own errors: a name, or the kind when it has none.
        XCTAssertEqual(Telemetry.reason(NotLinked.notLinked), "not_linked")
        XCTAssertEqual(Telemetry.reason(StoreFailure.unconfirmed), "store_unconfirmed")
        // Never words: a message-like code falls back to the kind.
        XCTAssertEqual(Telemetry.reason(AuthFailure(code: "Invalid login credentials")), "refused")
        XCTAssertEqual(Telemetry.reason(AuthFailure(code: String(repeating: "a", count: 61))), "refused")
    }

    func testSwiftNamesBecomeCodes() {
        XCTAssertEqual("tooManyCodes".snakeCased, "too_many_codes")
        XCTAssertEqual("mountainBiking".snakeCased, "mountain_biking")
        XCTAssertEqual("running".snakeCased, "running")
        XCTAssertTrue(PrivacyGuard.isCode("emailUnconfirmed".snakeCased))
    }

    func testProblemsAndLogsAreScrubbed() {
        Telemetry.log(.warning, "send failed for maya@example.com")
        XCTAssertEqual(crashes.logs, ["send failed for [email]"])
        Telemetry.problem("purchase credited late", "purchase", extra: ["seconds_to_credit": 900])
        XCTAssertEqual(crashes.messages, ["purchase credited late"])
    }

    func testProblemFingerprintsAreScrubbedToo() {
        Telemetry.problem("no card for maya@example.com", "discover")
        XCTAssertEqual(crashes.messages, ["no card for [email]"])
        XCTAssertEqual(crashes.reports.first?.fingerprint, ["discover", "no card for [email]"])
    }

    func testTraceFinishesTheSpanAndKeepsTheValue() async throws {
        let value = await Telemetry.trace("http.client", "POST rest/v1/rpc/discover") { _ in 42 }
        XCTAssertEqual(value, 42)
        do {
            _ = try await Telemetry.trace("media.upload", "profile photo") { _ -> Int in throw Bug() }
            XCTFail("the error goes through")
        } catch is Bug {}
        XCTAssertEqual(crashes.spans, [.ok, .failed])
    }

    func testACancelledTraceIsNotAFailure() async {
        do {
            _ = try await Telemetry.trace("http.client", "GET a") { _ -> Int in throw CancellationError() }
        } catch {}
        do {
            _ = try await Telemetry.trace("http.client", "GET b") { _ -> Int in throw URLError(.cancelled) }
        } catch {}
        do {
            _ = try await Telemetry.trace("http.client", "GET c") { _ -> Int in throw URLError(.timedOut) }
        } catch {}
        XCTAssertEqual(crashes.spans, [.cancelled, .cancelled, .failed])
    }

    // MARK: Config

    func testAnUnknownEnvironmentNeverCountsAsProduction() {
        for known in ["production", "staging"] { XCTAssertEqual(TelemetryConfig.environmentID(known), known) }
        for odd in ["", "$(APP_ENVIRONMENT)", "Production", "prod", "debug", "local"] {
            XCTAssertEqual(TelemetryConfig.environmentID(odd), "unknown", odd)
        }
    }

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

    func testOnlyTheExactEUHostsAreUsed() {
        func config(dsn: String = "", host: String) -> TelemetryConfig {
            TelemetryConfig(sentryDSN: dsn, postHogKey: "phc_x", postHogHost: host, environment: "production", version: "1", build: "1")
        }
        XCTAssertTrue(config(host: "https://eu.i.posthog.com").hasPostHog)
        XCTAssertTrue(config(host: "https://eu.i.posthog.com/").hasPostHog)
        // A prefix is not the host: another domain, a userinfo trick, a lookalike, a plain-http one, another port.
        for host in ["https://eu.evil.com", "https://eu.i.posthog.com@evil.com", "https://eu.i.posthog.com.evil.com",
                     "http://eu.i.posthog.com", "https://eu.i.posthog.com:8443", "https://eu.i.posthog.com/x",
                     "https://us.i.posthog.com", "eu.i.posthog.com", ""] {
            XCTAssertFalse(config(host: host).hasPostHog, host)
        }
        XCTAssertTrue(config(dsn: "https://abc123@o42.ingest.de.sentry.io/7", host: "").hasSentry)
        for dsn in ["https://abc123@o42.ingest.de.sentry.io.evil.com/7", "https://abc123@evil.com/o42.ingest.de.sentry.io/7",
                    "https://abc123@o42.ingest.de.sentry.io/7\n", "https://abc123@o42.ingest.us.sentry.io/7"] {
            XCTAssertFalse(config(dsn: dsn, host: "").hasSentry, dsn)
        }
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
