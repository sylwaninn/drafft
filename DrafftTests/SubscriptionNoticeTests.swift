import XCTest

/// The delete sheet's "deleting doesn't cancel drafft tempo" warning.
final class SubscriptionNoticeTests: XCTestCase {
    func testRenewingShowsWhateverTheWalletSays() {
        XCTAssertTrue(SubscriptionNotice.showsOnDelete(.renews, isPremium: true))
        XCTAssertTrue(SubscriptionNotice.showsOnDelete(.renews, isPremium: false))
    }

    func testCancelledHidesEvenWhileStillPremium() {
        // Billing follows the App Store: a cancelled subscription just ends.
        XCTAssertFalse(SubscriptionNotice.showsOnDelete(.ends, isPremium: true))
        XCTAssertFalse(SubscriptionNotice.showsOnDelete(.ends, isPremium: false))
    }

    func testUnknownAndNotPremiumHides() {
        XCTAssertFalse(SubscriptionNotice.showsOnDelete(.unknown, isPremium: false))
    }

    func testUnknownWhileServerSaysPremiumShows() {
        // RevenueCat hasn't reported yet: someone who pays must still see the warning.
        XCTAssertTrue(SubscriptionNotice.showsOnDelete(.unknown, isPremium: true))
    }
}
