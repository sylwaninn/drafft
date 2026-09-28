import XCTest

final class ChatPayloadTests: XCTestCase {
    private func extra(_ json: String) throws -> ChatPayload.Extra {
        try JSONDecoder().decode(ChatPayload.Extra.self, from: Data(json.utf8))
    }

    func testPlainMessageIsText() {
        XCTAssertEqual(ChatPayload.kind(text: "See you at 7?", extra: nil), .text("See you at 7?"))
    }

    func testSessionProposalShowsItsCard() throws {
        let id = UUID()
        let proposed = try extra(#"{"type":"session","sessionId":"\#(id.uuidString.lowercased())","status":"proposed"}"#)
        XCTAssertEqual(ChatPayload.kind(text: "Proposed a session", extra: proposed), .session(id: id))
    }

    func testSessionLaterStatusesAreHidden() throws {
        // The card shows the status; the server's English line never shows in the thread.
        for status in ["accepted", "declined", "cancelled"] {
            let e = try extra(#"{"type":"session","sessionId":"\#(UUID().uuidString)","status":"\#(status)"}"#)
            XCTAssertEqual(ChatPayload.kind(text: "Accepted the session", extra: e), .hidden)
        }
        let broken = try extra(#"{"type":"session","sessionId":"nope"}"#)
        XCTAssertEqual(ChatPayload.kind(text: "x", extra: broken), .hidden)
    }

    func testOpeners() throws {
        let ice = try extra(#"{"type":"icebreakerReply","quote":"I never fell","reply":"Lie!"}"#)
        XCTAssertEqual(ChatPayload.kind(text: "Lie!", extra: ice), .icebreakerReply(quote: "I never fell", reply: "Lie!"))
        let photo = try extra(#"{"type":"photoReply","key":"u/a/photos/1.jpg","reply":"Nice"}"#)
        XCTAssertEqual(ChatPayload.kind(text: "Nice", extra: photo), .photoReply(key: "u/a/photos/1.jpg", reply: "Nice"))
        let note = try extra(#"{"type":"superLikeNote"}"#)
        XCTAssertEqual(ChatPayload.kind(text: "Run Sunday?", extra: note), .text("Run Sunday?"))
    }

    func testUnknownKindFallsBackToItsText() throws {
        let e = try extra(#"{"type":"poll"}"#)
        XCTAssertEqual(ChatPayload.kind(text: "Vote", extra: e), .text("Vote"))
        XCTAssertEqual(ChatPayload.kind(text: "", extra: e), .hidden)
    }

    func testMediaAttachmentCarriesTheKeyNeverALink() throws {
        let media = ChatPayload.Media(kind: .video, key: "u/abc/chat/1.mp4", width: 720, height: 1280, duration: 12,
                                      posterKey: "u/abc/chat/2.jpg")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(media)) as? [String: Any])
        XCTAssertEqual(json["key"] as? String, "u/abc/chat/1.mp4")
        XCTAssertEqual(json["poster_key"] as? String, "u/abc/chat/2.jpg")
        XCTAssertFalse(json.values.contains { ($0 as? String)?.hasPrefix("http") == true })
        XCTAssertEqual(try JSONDecoder().decode(ChatPayload.Media.self, from: JSONEncoder().encode(media)), media)
        XCTAssertEqual(media.keys, ["u/abc/chat/1.mp4", "u/abc/chat/2.jpg"])
    }

    func testOwnChatKey() {
        XCTAssertTrue(ChatPayload.Media.isOwnChatKey("u/abc/chat/1.jpg", userID: "ABC"))
        XCTAssertFalse(ChatPayload.Media.isOwnChatKey("u/abc/photos/1.jpg", userID: "abc"))
        XCTAssertFalse(ChatPayload.Media.isOwnChatKey("u/xyz/chat/1.jpg", userID: "abc"))
        XCTAssertFalse(ChatPayload.Media.isOwnChatKey("u/abc/chat/../x.jpg", userID: "abc"))
    }
}
