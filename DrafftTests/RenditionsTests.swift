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

    /// The gallery, 393 × 440 pt at 3x, for a 4:5 photo: 1 179 px wanted, the 1 440 copy.
    private let gallery = Renditions.wanted(for: CGSize(width: 1_179, height: 1_320), aspect: 0.8, detail: true, slow: false)

    func testTheCardsCopyStandsInForAnOpenProfilesWiderOne() {
        XCTAssertEqual(gallery, 1_179, accuracy: 0.5)
        // The card left its 1 080 on this phone.
        XCTAssertEqual(Renditions.standIn(covering: gallery) { $0 == 1_080 }, 1_080)
        // The widest one here wins.
        XCTAssertEqual(Renditions.standIn(covering: gallery) { $0 == 640 || $0 == 1_080 }, 1_080)
        // 640 is just enough.
        XCTAssertEqual(Renditions.standIn(covering: gallery) { $0 == 640 }, 640)
    }

    func testNoStandInWhenACoveringCopyIsHere() {
        XCTAssertNil(Renditions.standIn(covering: gallery) { $0 == 1_440 })
        XCTAssertNil(Renditions.standIn(covering: gallery) { $0 == 1_080 || $0 == 1_440 })
        // The original covers everything.
        XCTAssertNil(Renditions.standIn(covering: gallery) { $0 == nil || $0 == 1_080 })
        // A larger copy than the covering one.
        XCTAssertNil(Renditions.standIn(covering: 1_000) { $0 == 1_440 })
    }

    func testNoStandInWhenNothingWorthShowingIsHere() {
        // A 320 copy is too soft to stand in.
        XCTAssertNil(Renditions.standIn(covering: gallery) { $0 == 320 })
        XCTAssertNil(Renditions.standIn(covering: gallery) { _ in false })
        // A small frame: its covering copy is the 640 or narrower.
        XCTAssertNil(Renditions.standIn(covering: 600) { $0 == 320 })
    }

    func testTheFivePercentToleranceDecidesBetweenCoveringAndStandingIn() {
        XCTAssertNil(Renditions.standIn(covering: 1_136) { $0 == 1_080 })
        XCTAssertEqual(Renditions.standIn(covering: 1_137) { $0 == 1_080 }, 1_080)
        XCTAssertNil(Renditions.standIn(covering: 1_515) { $0 == 1_440 })
        XCTAssertEqual(Renditions.standIn(covering: 1_516) { $0 == 1_440 }, 1_440)
    }

    func testAnyLadderCopyStandsInForTheOriginal() {
        XCTAssertEqual(Renditions.standIn(covering: 1_800) { $0 == 1_440 }, 1_440)
        XCTAssertNil(Renditions.standIn(covering: 1_800) { $0 == nil || $0 == 1_440 })
    }

    func testOnASlowLineTheCardsCopyIsTheGallerysOwn() {
        let slow = Renditions.wanted(for: CGSize(width: 1_179, height: 1_320), aspect: 0.8, detail: true, slow: true)
        XCTAssertEqual(Renditions.width(covering: slow), 1_080)
        XCTAssertNil(Renditions.standIn(covering: slow) { $0 == 1_080 })
        XCTAssertEqual(Renditions.standIn(covering: slow) { $0 == 640 }, 640)
    }

    func testEverydayPhotosAreWantedAt1080AtMost() {
        XCTAssertEqual(Renditions.wanted(for: card, aspect: 0.8, detail: false, slow: false), 1_080)
        XCTAssertEqual(Renditions.wanted(for: card, aspect: 0.8, detail: true, slow: false), 1_344, accuracy: 0.5)
    }

    func testAStandInIsNeverACopyTheRequestWouldPick() {
        let widths: [Int?] = Renditions.ladder.map(Optional.some) + [nil]
        for mask in 0..<(1 << widths.count) {
            let here = Set(widths.indices.filter { mask & (1 << $0) != 0 }.map { widths[$0] })
            for needed in stride(from: CGFloat(1), through: 2_500, by: 7) {
                let candidates = Renditions.candidates(covering: needed)
                guard let copy = Renditions.standIn(covering: needed, here: { here.contains($0) }) else { continue }
                XCTAssertTrue(here.contains(copy))
                XCTAssertGreaterThanOrEqual(copy, Renditions.standInMinimum)
                XCTAssertFalse(candidates.contains(copy))
                XCTAssertFalse(candidates.contains(where: { here.contains($0) }))
            }
        }
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
