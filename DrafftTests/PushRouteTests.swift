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
        XCTAssertEqual(route(["stream": ["type": "message.new"]]), PushRoute(kind: .message, destination: .chats, fallsBack: true))
    }

    func testSessionUpdatesOpenTheChat() {
        XCTAssertEqual(route(["match": match, "session": session]), PushRoute(kind: .sessionUpdate, destination: .chat(matchID)))
        XCTAssertEqual(route(["kind": "session_reminder", "match": match, "session": session]),
                       PushRoute(kind: .sessionReminder, destination: .chat(matchID)))
        XCTAssertEqual(route(["kind": "session_cancelled", "match": match, "session": session]),
                       PushRoute(kind: .sessionCancelled, destination: .chat(matchID)))
    }

    func testSessionCancelledWithoutMatchOpensSessions() {
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
        XCTAssertEqual(route([:]), PushRoute(kind: .unknown, destination: .discover, fallsBack: true))
        XCTAssertEqual(route(["kind": "something_new"]), PushRoute(kind: .unknown, destination: .discover, fallsBack: true))
        XCTAssertEqual(route(["kind": "something_new", "match": match]), PushRoute(kind: .unknown, destination: .chat(matchID)))
        XCTAssertEqual(route(["kind": "something_new", "tab": "likes"]), PushRoute(kind: .unknown, destination: .likes))
    }

    func testKindIsCaseInsensitive() {
        XCTAssertEqual(route(["kind": "MATCH", "match": match]).kind, .match)
    }

    func testOnlyAUUIDNamesAChat() {
        XCTAssertEqual(route(["kind": "match", "match": "../../etc"]), PushRoute(kind: .match, destination: .chats, fallsBack: true))
        XCTAssertEqual(route(["kind": "match", "match": 42]), PushRoute(kind: .match, destination: .chats, fallsBack: true))
        XCTAssertEqual(route(["kind": "match", "match": "  "]), PushRoute(kind: .match, destination: .chats, fallsBack: true))
        XCTAssertEqual(route(["match": "not-a-uuid"]), PushRoute(kind: .unknown, destination: .discover, fallsBack: true))
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
        let pending = PendingPushRoute(route: PushRoute(kind: .like, destination: .likes), tappedAt: tapped, coldStart: true,
                                       account: nil)
        XCTAssertFalse(pending.isExpired(at: tapped.addingTimeInterval(60)))
        XCTAssertFalse(pending.isExpired(at: tapped.addingTimeInterval(PendingPushRoute.lifetime)))
        XCTAssertTrue(pending.isExpired(at: tapped.addingTimeInterval(PendingPushRoute.lifetime + 1)))
    }

    // MARK: Payload edge cases

    func testTabValuesAreTrimmedAndCaseInsensitive() {
        let cases: [(String, PushRoute.Destination)] = [("sessions", .sessions), ("chats", .chats), ("discover", .discover),
                                                         ("  Likes ", .likes), ("SESSIONS", .sessions)]
        for (tab, destination) in cases {
            XCTAssertEqual(route(["kind": "x", "tab": tab]), PushRoute(kind: .unknown, destination: destination), tab)
        }
        XCTAssertEqual(route(["kind": "x", "tab": "me"]), PushRoute(kind: .unknown, destination: .discover, fallsBack: true))
        XCTAssertEqual(route(["kind": "x", "tab": 3]), PushRoute(kind: .unknown, destination: .discover, fallsBack: true))
    }

    func testKindlessInvalidChatIDOpensTheListAsAFallback() {
        XCTAssertEqual(route(["chatID": "nope"]), PushRoute(kind: .local, destination: .chats, fallsBack: true))
    }

    func testChatIDWinsOverMatchWhichWinsOverCid() {
        let other = "11111111-2222-3333-4444-555555555555"
        let third = "66666666-7777-8888-9999-aaaaaaaaaaaa"
        let info: [AnyHashable: Any] = ["chatID": other, "match": match, "stream": ["cid": "messaging:\(third)"]]
        XCTAssertEqual(route(info).destination, .chat(other))
        XCTAssertEqual(route(["match": match, "stream": ["cid": "messaging:\(third)"]]).destination, .chat(matchID))
        XCTAssertEqual(route(["chatID": "bad", "match": match]).destination, .chat(matchID))
        XCTAssertEqual(route(["match": "bad", "stream": ["cid": "messaging:\(third)"]]).destination, .chat(third))
    }

    func testMalformedCidOpensTheListAsAFallback() {
        for cid in ["messaging:", "messaging", ":", "messaging:a:b", "messaging:x:\(matchID)"] {
            XCTAssertEqual(route(["stream": ["cid": cid]]), PushRoute(kind: .message, destination: .chats, fallsBack: true), cid)
        }
    }

    func testSessionReminderWithoutMatchOpensSessions() {
        XCTAssertEqual(route(["kind": "session_reminder", "session": session]),
                       PushRoute(kind: .sessionReminder, destination: .sessions))
    }

    func testPhotoRefusalWithBlankMediaShowsNothingNew() {
        XCTAssertEqual(route(["kind": "photo_refused", "media": "  "]), PushRoute(kind: .photoRefused, destination: .current))
    }

    func testLikeWithAMatchStillOpensLikes() {
        XCTAssertEqual(route(["kind": "like", "match": match]), PushRoute(kind: .like, destination: .likes))
    }

    func testKindWithTrailingSpaceOrNotAStringIsNotRecognised() {
        XCTAssertEqual(route(["kind": "match ", "match": match]), PushRoute(kind: .unknown, destination: .chat(matchID)))
        // A non-string kind reads as no kind at all.
        XCTAssertEqual(route(["kind": 7, "match": match]), PushRoute(kind: .reaction, destination: .chat(matchID)))
        XCTAssertEqual(route(["kind": 7]), PushRoute(kind: .unknown, destination: .discover, fallsBack: true))
    }

    func testOnlyANamelessDestinationFallsBack() {
        XCTAssertFalse(route(["kind": "weekly_boost"]).fallsBack)
        XCTAssertFalse(route(["kind": "x", "tab": "discover"]).fallsBack)
        XCTAssertTrue(route(["kind": "match"]).fallsBack)
    }
}

/// The tap queue's rules (`PushTapQueue`): replace, take once, expiry, accounts, cold start.
final class PushTapQueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let like = PushRoute(kind: .like, destination: .likes)
    private let boost = PushRoute(kind: .weeklyBoost, destination: .discover)
    private var skipped: [PushRoute.Kind] = []

    private func queue() -> PushTapQueue { PushTapQueue { [self] in skipped.append($0.route.kind) } }

    func testANewerTapReplacesAndCountsTheOlder() {
        var q = queue()
        q.tap(like, account: "a", now: now)
        q.tap(boost, account: "a", now: now)
        XCTAssertEqual(skipped, [.like])
        XCTAssertEqual(q.take(now: now)?.route, boost)
    }

    func testATapIsTakenOnce() {
        var q = queue()
        q.tap(like, account: "a", now: now)
        XCTAssertNotNil(q.take(now: now))
        XCTAssertNil(q.take(now: now))
        XCTAssertTrue(skipped.isEmpty)
    }

    func testAnExpiredTapIsDroppedAndCounted() {
        var q = queue()
        q.tap(like, account: "a", now: now)
        XCTAssertNil(q.take(now: now.addingTimeInterval(PendingPushRoute.lifetime + 1)))
        XCTAssertEqual(skipped, [.like])
        XCTAssertNil(q.pending)
    }

    func testATapAtExactlyItsLifetimeIsFollowed() {
        var q = queue()
        q.tap(like, account: "a", now: now)
        XCTAssertNotNil(q.take(now: now.addingTimeInterval(PendingPushRoute.lifetime)))
    }

    func testDropCountsTheWaitingTap() {
        var q = queue()
        q.drop()
        XCTAssertTrue(skipped.isEmpty)
        q.tap(like, account: "a", now: now)
        q.drop()
        XCTAssertEqual(skipped, [.like])
        XCTAssertNil(q.take(now: now))
    }

    func testColdStartIsTheTapBeforeTheTabsWereFirstSeen() {
        var q = queue()
        q.tap(like, account: nil, now: now)
        XCTAssertEqual(q.pending?.coldStart, true)
        XCTAssertNil(q.pending?.account)
        _ = q.take(now: now)
        q.tap(like, account: "a", now: now)
        XCTAssertEqual(q.pending?.coldStart, false)
        XCTAssertEqual(q.pending?.account, "a")
    }

    func testATapWhileSignedOutInARunningAppIsDropped() {
        var q = queue()
        _ = q.take(now: now)
        q.tap(like, account: nil, now: now)
        XCTAssertNil(q.pending)
        XCTAssertEqual(skipped, [.like])
    }

    func testASignedOutTapAlsoCountsTheOneItReplaces() {
        var q = queue()
        _ = q.take(now: now)
        q.tap(like, account: "a", now: now)
        q.tap(boost, account: nil, now: now)
        XCTAssertEqual(skipped, [.like, .weeklyBoost])
        XCTAssertNil(q.pending)
    }
}
