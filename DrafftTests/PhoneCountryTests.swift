import XCTest

/// The phone step reads the country from the number itself when it's typed the international way,
/// whatever country was picked, and leaves a national number to the picked country.
@MainActor
final class PhoneCountryTests: XCTestCase {
    private func country(_ region: String) throws -> PhoneCountry {
        try XCTUnwrap(PhoneCountry.country(region))
    }

    func testPlusCodeNamesTheCountry() throws {
        let found = try XCTUnwrap(PhoneCountry.international("+33 6 12 34 56 78", from: country("US")))
        XCTAssertEqual(found.country.region, "FR")
        XCTAssertEqual(found.national.filter(\.isNumber), "0612345678")
    }

    func testExitCodeOfThePickedCountry() throws {
        let fromFrance = try XCTUnwrap(PhoneCountry.international("0044 7700 900123", from: country("FR")))
        XCTAssertEqual(fromFrance.country.region, "GB")
        let fromTheUS = try XCTUnwrap(PhoneCountry.international("011 44 7700 900123", from: country("US")))
        XCTAssertEqual(fromTheUS.country.region, "GB")
    }

    func testCodeAloneWhileTyping() throws {
        let found = try XCTUnwrap(PhoneCountry.international("+351", from: country("FR")))
        XCTAssertEqual(found.country.region, "PT")
        XCTAssertEqual(found.national, "")
        // Not a code yet: nothing changes.
        XCTAssertNil(PhoneCountry.international("+3", from: try country("FR")))
    }

    func testSharedCodeKeepsThePickedCountry() throws {
        XCTAssertEqual(try XCTUnwrap(PhoneCountry.international("+1", from: country("CA"))).country.region, "CA")
        XCTAssertEqual(try XCTUnwrap(PhoneCountry.international("+1", from: country("FR"))).country.region, "US")
    }

    func testNationalNumbersStayWithThePickedCountry() throws {
        XCTAssertNil(PhoneCountry.international("06 12 34 56 78", from: try country("FR")))
        XCTAssertNil(PhoneCountry.international("6 12 34 56 78", from: try country("FR")))
        XCTAssertNil(PhoneCountry.international("(415) 555-0132", from: try country("US")))
        XCTAssertNotNil(PhoneCountry.mobileNumber("0612345678", in: try country("FR")))
        XCTAssertNotNil(PhoneCountry.mobileNumber("612345678", in: try country("FR")))
    }
}
