import XCTest

final class DeckPaceTests: XCTestCase {
    func testAtFirstTenCardsLeftAskForMore() {
        XCTAssertEqual(DeckPace().lowWater, 10)
    }

    func testFastSwipesOnASlowLineAskEarlier() {
        var pace = DeckPace()
        pace.read(took: 3)
        pace.read(took: 3)
        for i in 0..<20 { pace.swiped(at: Double(i) * 0.25) }
        // Reads average 2.6 s by now, swipes 0.25 s: 11 swipes during a read, plus the photo window.
        XCTAssertEqual(pace.lowWater, 17)
        pace.read(took: 3)
        pace.read(took: 3)
        // Slower still: capped short of a whole batch.
        XCTAssertEqual(pace.lowWater, 18)
    }

    func testAPauseIsNotAPace() {
        var pace = DeckPace()
        pace.swiped(at: 0)
        pace.swiped(at: 60)
        XCTAssertEqual(pace.swipeSeconds, 0.8)
    }

    func testAQuickReadAtAnEasyPaceKeepsTheFloor() {
        var pace = DeckPace()
        pace.read(took: 0.2)
        pace.read(took: 0.2)
        for i in 0..<10 { pace.swiped(at: Double(i) * 2) }
        XCTAssertEqual(pace.lowWater, 10)
    }
}
