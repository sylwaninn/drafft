import XCTest

final class ThumbHashTests: XCTestCase {
    /// A 100 × 60 landscape: red to blue left to right, brighter at the top.
    private func gradient(width w: Int = 100, height h: Int = 60) -> [UInt8] {
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let t = Double(x) / Double(w - 1), light = 1 - 0.5 * Double(y) / Double(h - 1)
                rgba[i] = UInt8(255 * (1 - t) * light)
                rgba[i + 1] = UInt8(60 * light)
                rgba[i + 2] = UInt8(255 * t * light)
            }
        }
        return rgba
    }

    private func average(_ rgba: [UInt8], channel: Int) -> Double {
        stride(from: channel, to: rgba.count, by: 4).reduce(0) { $0 + Double(rgba[$1]) } / Double(rgba.count / 4)
    }

    func testRoundTripKeepsShapeAndColours() throws {
        let source = gradient()
        let hash = ThumbHash.encode(width: 100, height: 60, rgba: source)
        XCTAssertLessThanOrEqual(hash.count, 25)
        let decoded = try XCTUnwrap(ThumbHash.decode(hash))
        // Landscape, width capped at 32, height from the approximate ratio.
        XCTAssertEqual(decoded.width, 32)
        XCTAssertEqual(decoded.rgba.count, decoded.width * decoded.height * 4)
        XCTAssertEqual(Double(decoded.width) / Double(decoded.height), 100.0 / 60, accuracy: 0.35)
        for channel in 0..<3 {
            XCTAssertEqual(average(decoded.rgba, channel: channel), average(source, channel: channel), accuracy: 12,
                           "channel \(channel)")
        }
        // The left edge stays redder than the right one.
        let row = decoded.height / 2, left = row * decoded.width * 4, right = left + (decoded.width - 1) * 4
        XCTAssertGreaterThan(decoded.rgba[left], decoded.rgba[right])
        XCTAssertLessThan(decoded.rgba[left + 2], decoded.rgba[right + 2])
        XCTAssertTrue(stride(from: 3, to: decoded.rgba.count, by: 4).allSatisfy { decoded.rgba[$0] == 255 })
    }

    func testPortraitAndBase64Image() throws {
        var portrait = [UInt8](repeating: 255, count: 40 * 90 * 4)
        for i in stride(from: 0, to: portrait.count, by: 4) { portrait[i] = 30; portrait[i + 1] = 140; portrait[i + 2] = 90 }
        let base64 = Data(ThumbHash.encode(width: 40, height: 90, rgba: portrait)).base64EncodedString()
        let image = try XCTUnwrap(ThumbHash.image(fromBase64: base64))
        XCTAssertEqual(image.height, 32)
        XCTAssertLessThan(image.width, image.height)
    }

    func testRejectsGarbage() {
        XCTAssertNil(ThumbHash.decode([]))
        XCTAssertNil(ThumbHash.decode([1, 2, 3]))
        XCTAssertNil(ThumbHash.decode([0x1f, 0x2e, 0x3d, 0x07, 0x00]))
        XCTAssertNil(ThumbHash.image(fromBase64: "not base64"))
    }

    /// Decoding a preview: what a photo view pays once (then cached by key).
    func testDecodeSpeed() {
        let hash = ThumbHash.encode(width: 100, height: 60, rgba: gradient())
        measure {
            for _ in 0..<100 { _ = ThumbHash.decode(hash) }
        }
    }
}
