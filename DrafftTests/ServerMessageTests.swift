import XCTest

/// The server's refusal codes the consent relies on, and how a code is told from a sentence.
final class ServerMessageTests: XCTestCase {
    func testConsentCodesHaveWords() {
        XCTAssertNotNil(ServerMessage.text(forCode: "terms_required"))
        XCTAssertNotNil(ServerMessage.text(forCode: "sensitive_consent_required"))
    }

    func testSessionAndTargetCodesHaveWords() {
        // An edge function's 401 and a swipe or block on a profile that can't be targeted.
        XCTAssertNotNil(ServerMessage.text(forCode: "unauthenticated"))
        XCTAssertEqual(ServerMessage.text(forCode: "invalid_target"), ServerMessage.text(forCode: "not_eligible"))
    }

    func testConnectionAdviceOnlyWhenOffline() {
        XCTAssertTrue(ServerMessage.isOffline(URLError(.notConnectedToInternet)))
        XCTAssertTrue(ServerMessage.isOffline(URLError(.timedOut)))
        XCTAssertFalse(ServerMessage.isOffline(URLError(.cancelled)))
        // Not a transport error (the server answered, or something else failed): never connection advice.
        XCTAssertFalse(ServerMessage.isOffline(NSError(domain: "server", code: 500)))
    }

    func testUnknownCodeHasNoWords() {
        // The caller then shows its own line: accept_terms' own codes are handled by TermsConsent.
        XCTAssertNil(ServerMessage.text(forCode: "invalid_terms_version"))
        XCTAssertNil(ServerMessage.text(forCode: "something_new"))
    }

    func testCodeOrSentence() {
        XCTAssertTrue(ServerMessage.isCode("sensitive_consent_required"))
        XCTAssertTrue(ServerMessage.isCode("42703"))
        // PostgREST's own message (a missing column or function) is a sentence, never shown.
        XCTAssertFalse(ServerMessage.isCode("column profiles.terms_version does not exist"))
        XCTAssertFalse(ServerMessage.isCode(""))
    }
}
