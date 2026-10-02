import XCTest

/// Every payload drafft-backend and Stream send (PushRoute's list), and where its tap leads.
final class PushRouteTests: XCTestCase {
    private let match = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
    private let matchID = "3f2504e0-4f89-11d3-9a0c-0305e82c3301"
    private let session = "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"

    private func route(_ info: [AnyHashable: Any]) -> PushRoute { PushRoute(userInfo: info) }

    func testLikesOpenLikes() {
        XCTAssertEqual(route(["aps": [:], "kind": "like", "tab": "likes"]), PushRoute(kind: .like, destination: .likes))
        XCTAssertEqual(route(["kind": "super_like", "tab": "likes"]), PushRoute(kind: .superLike, destination: .likes))
    }

    func testMatchOpensItsChat() {
        XCTAssertEqual(route(["kind": "match", "match": match]), PushRoute(kind: .match, destination: .chat(matchID)))
    }

    func testStreamMessageOpensItsChat() {
        let info: [AnyHashable: Any] = [
            "match": matchID,
            "stream": ["sender": "stream.chat", "type": "message.new", "version": "v2", "id": "m1",
                       "cid": "messaging:\(matchID)"]
        ]
        XCTAssertEqual(route(info), PushRoute(kind: .message, destination: .chat(matchID)))
    }

    func testStreamMessageWithoutMatchFallsBackToItsChannel() {
        let info: [AnyHashable: Any] = ["stream": ["type": "message.new", "cid": "messaging:\(match)"]]
        XCTAssertEqual(route(info), PushRoute(kind: .message, destination: .chat(matchID)))
    }

    func testStreamMessageWithoutAnyChatOpensTheList() {
        XCTAssertEqual(route(["stream": ["type": "message.new"]]), PushRoute(kind: .message, destination: .chats))
    }

    func testSessionUpdatesOpenTheChat() {
        XCTAssertEqual(route(["match": match, "session": session]), PushRoute(kind: .sessionUpdate, destination: .chat(matchID)))
        XCTAssertEqual(route(["kind": "session_reminder", "match": match, "session": session]),
                       PushRoute(kind: .sessionReminder, destination: .chat(matchID)))
        XCTAssertEqual(route(["kind": "session_cancelled", "match": match, "session": session]),
                       PushRoute(kind: .sessionCancelled, destination: .chat(matchID)))
    }

    func testSessionCancelledWithItsMatchOpensSessions() {
        XCTAssertEqual(route(["kind": "session_cancelled", "session": session]),
                       PushRoute(kind: .sessionCancelled, destination: .sessions))
    }

    func testReactionOpensTheChat() {
        XCTAssertEqual(route(["match": match]), PushRoute(kind: .reaction, destination: .chat(matchID)))
    }

    func testLocalNotificationOpensTheChat() {
        XCTAssertEqual(route(["chatID": matchID]), PushRoute(kind: .local, destination: .chat(matchID)))
    }

    func testAccountPushes() {
        XCTAssertEqual(route(["kind": "photo_refused", "media": "abc"]),
                       PushRoute(kind: .photoRefused, destination: .photoRefusal(mediaID: "abc")))
        XCTAssertEqual(route(["kind": "photo_refused"]), PushRoute(kind: .photoRefused, destination: .current))
        XCTAssertEqual(route(["kind": "moderation"]), PushRoute(kind: .moderation, destination: .discover))
        XCTAssertEqual(route(["kind": "weekly_boost"]), PushRoute(kind: .weeklyBoost, destination: .discover))
    }

    func testUnknownPayloadsOpenDiscoverOrWhatTheyName() {
        XCTAssertEqual(route([:]), PushRoute(kind: .unknown, destination: .discover))
        XCTAssertEqual(route(["kind": "something_new"]), PushRoute(kind: .unknown, destination: .discover))
        XCTAssertEqual(route(["kind": "something_new", "match": match]), PushRoute(kind: .unknown, destination: .chat(matchID)))
        XCTAssertEqual(route(["kind": "something_new", "tab": "likes"]), PushRoute(kind: .unknown, destination: .likes))
    }

    func testKindIsCaseInsensitive() {
        XCTAssertEqual(route(["kind": "MATCH", "match": match]).kind, .match)
    }

    func testOnlyAUUIDNamesAChat() {
        XCTAssertEqual(route(["kind": "match", "match": "../../etc"]), PushRoute(kind: .match, destination: .chats))
        XCTAssertEqual(route(["kind": "match", "match": 42]), PushRoute(kind: .match, destination: .chats))
        XCTAssertEqual(route(["kind": "match", "match": "  "]), PushRoute(kind: .match, destination: .chats))
        XCTAssertEqual(route(["match": "not-a-uuid"]), PushRoute(kind: .unknown, destination: .discover))
    }

    func testKindsAndDestinationsAreTelemetryCodes() {
        let codes = PushRoute.Kind.allCases.map(\.rawValue)
            + [PushRoute.Destination.chat(matchID), .chats, .likes, .sessions, .discover,
               .photoRefusal(mediaID: "x"), .current].map(\.code)
        for code in codes { XCTAssertTrue(PrivacyGuard.isValueCode(code), code) }
    }

    func testOnlyPagesClearPresentedScreens() {
        XCTAssertTrue(PushRoute.Destination.chat(matchID).clearsPresentedScreens)
        XCTAssertTrue(PushRoute.Destination.likes.clearsPresentedScreens)
        XCTAssertFalse(PushRoute.Destination.photoRefusal(mediaID: "x").clearsPresentedScreens)
        XCTAssertFalse(PushRoute.Destination.current.clearsPresentedScreens)
    }

    func testAPendingTapExpires() {
        let tapped = Date(timeIntervalSince1970: 1_000_000)
        let pending = PendingPushRoute(route: PushRoute(kind: .like, destination: .likes), tappedAt: tapped, coldStart: true)
        XCTAssertFalse(pending.isExpired(at: tapped.addingTimeInterval(60)))
        XCTAssertTrue(pending.isExpired(at: tapped.addingTimeInterval(PendingPushRoute.lifetime + 1)))
    }
}
