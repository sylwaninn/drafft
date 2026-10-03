import XCTest

final class RenditionsTests: XCTestCase {
    /// A deck card on a 6.3" iPhone: 361 × 560 pt at 3x.
    private let card = CGSize(width: 1_083, height: 1_680)

    func testPortraitPhotoFillsTheCardFromTheSmallestCoveringCopy() {
        // 4:5: the card's height decides, 1 344 px wide, the 1 440 copy.
        let needed = Renditions.neededWidth(for: card, aspect: 0.8)
        XCTAssertEqual(needed, 1_344, accuracy: 0.5)
        XCTAssertEqual(Renditions.width(covering: needed), 1_440)
    }

    func testLandscapePhotoOnATallCardNeedsTheOriginal() {
        let needed = Renditions.neededWidth(for: card, aspect: 4.0 / 3.0)
        XCTAssertNil(Renditions.width(covering: needed))
        XCTAssertEqual(Renditions.candidates(covering: needed), [nil])
    }

    func testUnknownProportionsCountAsSquare() {
        XCTAssertEqual(Renditions.neededWidth(for: card, aspect: nil), 1_680)
        XCTAssertEqual(Renditions.neededWidth(for: card, aspect: 0), 1_680)
    }

    func testAFivePercentUpscaleSavesAStep() {
        XCTAssertEqual(Renditions.width(covering: 1_120), 1_080)
        XCTAssertEqual(Renditions.width(covering: 1_150), 1_440)
    }

    func testLargerCopiesStandInBestFirst() {
        XCTAssertEqual(Renditions.candidates(covering: 600), [640, 1_080, 1_440, nil])
        XCTAssertEqual(Renditions.candidates(covering: 72), [160, 320, 640, 1_080, 1_440, nil])
    }

    func testEverydayPhotosStopAt1080AndAnOpenProfileGoesFurther() {
        XCTAssertEqual(Renditions.asked(1_344, detail: false), 1_080)
        XCTAssertEqual(Renditions.asked(1_344, detail: true), 1_344)
        XCTAssertEqual(Renditions.asked(600, detail: false), 600)
        XCTAssertEqual(Renditions.width(covering: Renditions.asked(1_344, detail: false)), 1_080)
    }

    func testTheCardsCopyStandsInForAnOpenProfilesWiderOne() {
        // The gallery, 393 × 440 pt at 3x, wants 1 440; the card left its 1 080 on this phone.
        let needed = Renditions.neededWidth(for: CGSize(width: 1_179, height: 1_320), aspect: 0.8)
        XCTAssertEqual(Renditions.standIn(covering: needed) { $0 == 1_080 }, 1_080)
        // The widest one below wins.
        XCTAssertEqual(Renditions.standIn(covering: needed) { $0 == 640 || $0 == 1_080 }, 1_080)
    }

    func testNoStandInWhenTheRightCopyIsHereOrOnlyATinyOneIs() {
        XCTAssertNil(Renditions.standIn(covering: 1_179) { $0 == 1_440 })
        XCTAssertNil(Renditions.standIn(covering: 1_179) { $0 == 1_080 || $0 == 1_440 })
        // A chat avatar's copy says no more than the blurred preview.
        XCTAssertNil(Renditions.standIn(covering: 1_179) { $0 == 320 })
        XCTAssertNil(Renditions.standIn(covering: 1_179) { _ in false })
    }

    func testAnyLadderCopyStandsInForTheOriginal() {
        XCTAssertEqual(Renditions.standIn(covering: 1_800) { $0 == 1_440 }, 1_440)
    }

    func testPreviewIsAQuarterOfTheWidth() {
        XCTAssertEqual(Renditions.previewWidth(covering: 1_344), 320)
        XCTAssertEqual(Renditions.previewWidth(covering: 300), 160)
    }

    func testDecodeSizeKeepsTheFramesProportions() {
        let sharp = Renditions.decodeSize(for: card)
        XCTAssertEqual(sharp, CGSize(width: 1_088, height: 1_688))
        // The small copy, a third of the pixels: the same proportions, so it's cropped like the sharp one.
        let small = Renditions.decodeSize(for: CGSize(width: card.width / 3, height: card.height / 3))
        XCTAssertEqual(small.width / small.height, sharp.width / sharp.height, accuracy: 0.002)
        XCTAssertEqual(Renditions.decodeSize(for: CGSize(width: 10, height: 0)), CGSize(width: 64, height: 64))
    }
}
