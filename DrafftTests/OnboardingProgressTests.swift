import XCTest

/// Sign-up progress saved on the phone: what an older build saved must still resume.
final class OnboardingProgressTests: XCTestCase {
    /// As the build before the recorded consent saved it: an `acceptedTerms` flag, no `termsVersion`.
    private let savedBeforeTermsVersion = """
    {"name": "Maya", "language": "fr", "acceptedTerms": true, "verifiedPhone": "+33 6 12 34 56 78",
     "interestedIn": ["Men"], "sports": [{"sport": "trail", "perWeek": 2}], "photos": [], "voiceDuration": 0,
     "prompts": [], "bio": "", "lifestyle": [], "furthest": 4}
    """

    func testDecodesProgressSavedBeforeTermsVersion() throws {
        let p = try JSONDecoder().decode(OnboardingProgress.self, from: Data(savedBeforeTermsVersion.utf8))
        XCTAssertEqual(p.name, "Maya")
        XCTAssertEqual(p.furthest, 4)
        XCTAssertNil(p.termsVersion)
        // Nothing on record from that build: the rules step asks again, boxes unticked.
        XCTAssertEqual(ConsentDraft.restored(recordedVersion: p.termsVersion), ConsentDraft())
    }

    func testKeepsTheRecordedVersion() throws {
        var p = OnboardingProgress()
        p.termsVersion = TermsConsent.version
        let back = try JSONDecoder().decode(OnboardingProgress.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        XCTAssertEqual(ConsentDraft.restored(recordedVersion: back.termsVersion), .accepted)
    }
}
