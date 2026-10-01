import XCTest

final class DiscoveryFreshnessTests: XCTestCase {
    func testNeverReadIsAlwaysDue() {
        let fresh = DiscoveryFreshness()
        XCTAssertTrue(fresh.isDue(.deck, for: .tabShown, now: 0))
        XCTAssertTrue(fresh.isDue(.likes, for: .foreground, now: 0))
    }

    func testAQuickTripAwayReadsNothingALongOneReadsAgain() {
        var fresh = DiscoveryFreshness()
        let read = fresh.start(.deck, now: 100)
        XCTAssertTrue(fresh.finish(read, ok: true))
        XCTAssertFalse(fresh.isDue(.deck, for: .foreground, now: 110))
        XCTAssertTrue(fresh.isDue(.deck, for: .foreground, now: 130))
        XCTAssertFalse(fresh.isDue(.deck, for: .tabShown, now: 150))
        XCTAssertTrue(fresh.isDue(.deck, for: .tabShown, now: 160))
    }

    func testEnteringAndReconnectingAlwaysRead() {
        var fresh = DiscoveryFreshness()
        let read = fresh.start(.matches, now: 100)
        XCTAssertTrue(fresh.finish(read, ok: true))
        XCTAssertTrue(fresh.isDue(.matches, for: .entered, now: 100))
        XCTAssertTrue(fresh.isDue(.matches, for: .reconnected, now: 100))
    }

    func testAReadOnItsWayCountsUntilItLooksLost() {
        var fresh = DiscoveryFreshness()
        _ = fresh.start(.likes, now: 100)
        XCTAssertFalse(fresh.isDue(.likes, for: .foreground, now: 105))
        XCTAssertTrue(fresh.isDue(.likes, for: .foreground, now: 100 + DiscoveryFreshness.lostAfter))
    }

    func testAFailedReadLeavesThePartDue() {
        var fresh = DiscoveryFreshness()
        let read = fresh.start(.likesLeft, now: 100)
        XCTAssertFalse(fresh.finish(read, ok: false))
        XCTAssertTrue(fresh.isDue(.likesLeft, for: .foreground, now: 101))
    }

    func testAnOlderAnswerLandingLastIsDropped() {
        var fresh = DiscoveryFreshness()
        let older = fresh.start(.matches, now: 100)
        let newer = fresh.start(.matches, now: 101)
        XCTAssertTrue(fresh.finish(newer, ok: true))
        XCTAssertFalse(fresh.finish(older, ok: true))
        // Fresh as of the newer read.
        XCTAssertFalse(fresh.isDue(.matches, for: .foreground, now: 130))
        XCTAssertTrue(fresh.isDue(.matches, for: .foreground, now: 131))
    }

    func testAnOlderAnswerLandingFirstStillShows() {
        var fresh = DiscoveryFreshness()
        let older = fresh.start(.likes, now: 100)
        let newer = fresh.start(.likes, now: 101)
        XCTAssertTrue(fresh.finish(older, ok: true))
        XCTAssertTrue(fresh.finish(newer, ok: true))
    }

    func testPartsAgeOnTheirOwn() {
        var fresh = DiscoveryFreshness()
        let likes = fresh.start(.likes, now: 100)
        XCTAssertTrue(fresh.finish(likes, ok: true))
        XCTAssertFalse(fresh.isDue(.likes, for: .foreground, now: 110))
        XCTAssertTrue(fresh.isDue(.deck, for: .foreground, now: 110))
    }
}
