import XCTest

final class LikeAgeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func age(_ seconds: TimeInterval) -> LikeAge { LikeAge(from: now.addingTimeInterval(-seconds), to: now) }

    func testUnderAMinuteIsJustNow() {
        XCTAssertEqual(age(0), .now)
        XCTAssertEqual(age(59), .now)
        // A clock a little ahead of the server's.
        XCTAssertEqual(age(-30), .now)
    }

    func testMinutesThenHours() {
        XCTAssertEqual(age(60), .minutes(1))
        XCTAssertEqual(age(59 * 60 + 59), .minutes(59))
        XCTAssertEqual(age(3_600), .hours(1))
        XCTAssertEqual(age(23 * 3_600 + 3_599), .hours(23))
    }

    func testDaysThenMonths() {
        XCTAssertEqual(age(86_400), .days(1))
        XCTAssertEqual(age(29 * 86_400 + 86_399), .days(29))
        XCTAssertEqual(age(30 * 86_400), .months(1))
        XCTAssertEqual(age(59 * 86_400), .months(1))
        XCTAssertEqual(age(60 * 86_400), .months(2))
        XCTAssertEqual(age(364 * 86_400), .months(11))
    }

    func testYears() {
        XCTAssertEqual(age(365 * 86_400), .years(1))
        XCTAssertEqual(age(729 * 86_400), .years(1))
        XCTAssertEqual(age(730 * 86_400), .years(2))
    }

    func testNoDateNoLabel() {
        XCTAssertNil(LikeAge.text(of: nil, at: now))
    }

    func testNewestFirstWhateverTheKind() {
        struct Row { let id: String; let at: Date? }
        let rows = [Row(id: "old", at: now.addingTimeInterval(-300)), Row(id: "none", at: nil),
                    Row(id: "new", at: now.addingTimeInterval(-10)), Row(id: "b", at: now.addingTimeInterval(-100)),
                    Row(id: "a", at: now.addingTimeInterval(-100))]
        let sorted = LikeOrder.newestFirst(rows, date: \.at, id: \.id).map(\.id)
        XCTAssertEqual(sorted, ["new", "a", "b", "old", "none"])
    }
}
