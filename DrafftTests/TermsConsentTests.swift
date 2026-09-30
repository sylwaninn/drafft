import XCTest

/// The consent rules: the version rule, what the profile row says (the bytes `ProfileSync` hands
/// over, fresh or cached), what a refused `accept_terms` does, and the two boxes.
final class TermsConsentTests: XCTestCase {
    // MARK: Version

    func testTheShippedVersionIsAnISODate() {
        // The server refuses anything else (invalid_terms_version), and the text comparison needs it.
        XCTAssertTrue(TermsConsent.isWellFormed(TermsConsent.version))
    }

    func testVersionRule() {
        XCTAssertTrue(TermsConsent.isCurrent(TermsConsent.version))
        XCTAssertTrue(TermsConsent.isCurrent("2099-01-01"), "newer terms from a newer build must not ask again")
        XCTAssertFalse(TermsConsent.isCurrent("2026-01-01"))
        XCTAssertFalse(TermsConsent.isCurrent(nil))
        XCTAssertFalse(TermsConsent.isCurrent(""))
        XCTAssertFalse(TermsConsent.isCurrent("2099-1-1"), "not zero-padded: compares wrong as text")
        XCTAssertFalse(TermsConsent.isCurrent("latest"))
        XCTAssertFalse(TermsConsent.isCurrent("2099-01-01T00:00:00Z"))
    }

    // MARK: Record

    private func record(_ version: String?, at: String? = "2026-09-30T08:00:00Z", sensitive: String? = "2026-09-30T08:00:00Z")
        -> TermsConsent.Record? {
        TermsConsent.Record(version: version, acceptedAt: at, sensitiveConsentAt: sensitive)
    }

    func testRecordNeedsVersionAndDate() {
        XCTAssertNil(record(nil))
        XCTAssertNil(record(TermsConsent.version, at: nil))
        XCTAssertNotNil(record(TermsConsent.version, sensitive: nil))
    }

    func testIsNeeded() {
        XCTAssertTrue(TermsConsent.isNeeded(nil))
        XCTAssertFalse(TermsConsent.isNeeded(record(TermsConsent.version)))
        XCTAssertFalse(TermsConsent.isNeeded(record("2099-01-01")))
        XCTAssertTrue(TermsConsent.isNeeded(record("2026-01-01")))
        XCTAssertTrue(TermsConsent.isNeeded(record(TermsConsent.version, sensitive: nil)))
    }

    // MARK: The profile row

    private func gate(_ fields: String) -> TermsConsent.Gate {
        TermsConsent.gate(fromProfileRow: Data(#"[{"name": "Maya", "paused": false\#(fields)}]"#.utf8))
    }

    private let onboarded = #", "onboarded_at": "2026-09-01T10:00:00Z""#

    private func columns(_ version: String?, at: String? = "2026-09-30T08:00:00Z", sensitive: String? = "2026-09-30T08:00:00Z") -> String {
        func json(_ value: String?) -> String { value.map { "\"\($0)\"" } ?? "null" }
        return #", "terms_version": \#(json(version)), "terms_accepted_at": \#(json(at)), "sensitive_consent_at": \#(json(sensitive))"#
    }

    func testOnboardedWithNothingOnRecordIsRequired() {
        XCTAssertEqual(gate(onboarded + columns(nil, at: nil, sensitive: nil)), .required)
    }

    func testCurrentVersionWithConsentIsAccepted() {
        XCTAssertEqual(gate(onboarded + columns(TermsConsent.version)), .accepted)
    }

    func testOlderVersionIsRequired() {
        XCTAssertEqual(gate(onboarded + columns("2026-01-01")), .required)
    }

    func testNewerServerVersionIsAccepted() {
        // An older build must not ask in a loop after a newer one recorded newer terms.
        XCTAssertEqual(gate(onboarded + columns("2027-01-01")), .accepted)
    }

    func testTermsWithoutSensitiveConsentAreRequired() {
        XCTAssertEqual(gate(onboarded + columns(TermsConsent.version, sensitive: nil)), .required)
    }

    func testNotOnboardedIsNeverAsked() {
        // Sign-up records the consent itself: the cover must not show over it.
        XCTAssertEqual(gate(columns(nil, at: nil, sensitive: nil)), .accepted)
        XCTAssertEqual(gate(#", "onboarded_at": null"# + columns(nil, at: nil, sensitive: nil)), .accepted)
    }

    func testRowWithoutTheColumnsIsUnknown() {
        // A backend without drafft-backend #48, or a copy cached before this build: not "never consented".
        XCTAssertEqual(gate(onboarded), .unknown)
        XCTAssertEqual(gate(onboarded + #", "terms_version": null"#), .unknown)
    }

    func testBytesThatAreNotARowAreUnknown() {
        XCTAssertEqual(TermsConsent.gate(fromProfileRow: Data("[]".utf8)), .unknown)
        XCTAssertEqual(TermsConsent.gate(fromProfileRow: Data("not json".utf8)), .unknown)
    }

    // MARK: A refused accept_terms

    func testSessionProblemsSignOut() {
        XCTAssertEqual(TermsConsent.failure(code: "unauthenticated", offline: false), .signOut)
        XCTAssertEqual(TermsConsent.failure(code: "not_found", offline: false), .signOut)
    }

    func testNewerTermsOnRecordAskForAnUpdate() {
        XCTAssertEqual(TermsConsent.failure(code: "invalid_terms_version", offline: false),
                       .message(L("drafft has newer terms. Update the app to continue.")))
    }

    func testKnownCodesUseTheirWords() {
        XCTAssertEqual(TermsConsent.failure(code: "sensitive_consent_required", offline: false),
                       .message(ServerMessage.text(forCode: "sensitive_consent_required") ?? ""))
        XCTAssertEqual(TermsConsent.failure(code: "terms_required", offline: false),
                       .message(ServerMessage.text(forCode: "terms_required") ?? ""))
    }

    func testUnknownCodeIsGeneric() {
        XCTAssertEqual(TermsConsent.failure(code: "something_new", offline: false), .message(ServerMessage.generic))
    }

    func testNoCodeSaysConnectionOnlyWhenOffline() {
        XCTAssertEqual(TermsConsent.failure(code: nil, offline: true),
                       .message(L("Your consent couldn't be saved. Check your connection and try again.")))
        XCTAssertEqual(TermsConsent.failure(code: nil, offline: false), .message(ServerMessage.generic))
    }

    // MARK: The two boxes

    func testBothBoxesAreRequired() {
        XCTAssertFalse(ConsentDraft().isComplete)
        XCTAssertFalse(ConsentDraft(terms: true, sensitiveData: false).isComplete)
        XCTAssertFalse(ConsentDraft(terms: false, sensitiveData: true).isComplete)
        XCTAssertTrue(ConsentDraft(terms: true, sensitiveData: true).isComplete)
    }

    func testResumeTicksOnlyForTheCurrentVersion() {
        XCTAssertEqual(ConsentDraft.restored(recordedVersion: TermsConsent.version), .accepted)
        XCTAssertEqual(ConsentDraft.restored(recordedVersion: "2026-01-01"), ConsentDraft())
        XCTAssertEqual(ConsentDraft.restored(recordedVersion: nil), ConsentDraft())
    }
}
