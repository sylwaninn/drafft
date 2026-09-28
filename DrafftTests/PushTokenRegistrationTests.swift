import XCTest

final class PushTokenRegistrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let account = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        suite = "PushTokenRegistrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func registration() -> PushTokenRegistration { PushTokenRegistration(defaults: defaults) }

    func testFirstTokenIsSent() {
        XCTAssertTrue(registration().needsSending(token: "a", account: account, environment: "production", now: now))
    }

    func testSameTokenIsNotSentAgain() {
        registration().markSent(token: "a", account: account, environment: "production", at: now)
        XCTAssertFalse(registration().needsSending(token: "a", account: account, environment: "production",
                                                   now: now.addingTimeInterval(60)))
    }

    func testChangedTokenAccountOrEnvironmentIsSent() {
        registration().markSent(token: "a", account: account, environment: "production", at: now)
        let reg = registration()
        XCTAssertTrue(reg.needsSending(token: "b", account: account, environment: "production", now: now))
        XCTAssertTrue(reg.needsSending(token: "a", account: UUID(), environment: "production", now: now))
        XCTAssertTrue(reg.needsSending(token: "a", account: account, environment: "sandbox", now: now))
    }

    func testSentAgainAfterADay() {
        registration().markSent(token: "a", account: account, environment: "production", at: now)
        XCTAssertTrue(registration().needsSending(token: "a", account: account, environment: "production",
                                                  now: now.addingTimeInterval(PushTokenRegistration.refreshInterval)))
    }

    func testClockMovedBackSendsAgain() {
        registration().markSent(token: "a", account: account, environment: "production", at: now)
        XCTAssertTrue(registration().needsSending(token: "a", account: account, environment: "production",
                                                  now: now.addingTimeInterval(-60)))
    }

    func testForgetSendsAgain() {
        let reg = registration()
        reg.markSent(token: "a", account: account, environment: "production", at: now)
        reg.forget()
        XCTAssertTrue(reg.needsSending(token: "a", account: account, environment: "production", now: now))
    }
}
