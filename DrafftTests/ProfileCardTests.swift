import XCTest

/// The cards `discover`, `liked_me`, `my_matches` and `get_cards` send, decoded as the server shapes them
/// (`private.rebuild_card` and `private.sign_card` in drafft-backend).
final class ProfileCardTests: XCTestCase {
    private let id = "0B7C1E2A-6D3F-4C55-9E7A-1F2B3C4D5E6F"

    private func card(_ extra: String = "") -> String {
        """
        {"id": "\(id)", "name": "Maya", "gender": "woman", "pronouns": "she/her", "neighborhood": "Belleville",
         "bio": "Slow long runs.", "goal": "First 50k", "favoriteSpot": "Buttes-Chaumont",
         "vitals": {"drinks": "Socially", "smokes": "Never", "diet": "", "chronotype": "Early bird"},
         "icebreaker": {"kind": "joke", "setup": "Why?", "punchline": "Because."},
         "voiceIntro": {"key": "u/\(id.lowercased())/voice/a.m4a", "url": "https://media.example/u/v?exp=1&sig=x",
                        "duration": 12.5, "levels": [0.1, 0.5]},
         "media": [
           {"id": "m1", "kind": "photo", "key": "u/x/photos/1.jpg", "url": "https://media.example/u/x/photos/1.jpg?exp=1&sig=a",
            "width": 1080, "height": 1440, "thumbhash": null, "duration": null, "posterKey": null, "posterUrl": null},
           {"id": "m2", "kind": "video", "key": "u/x/videos/2.mp4", "url": null},
           {"id": "m3", "kind": "photo", "key": "u/x/photos/3.jpg"}
         ],
         "sports": [{"sport": "trail", "perWeek": 2}, {"sport": "yoga", "perWeek": 1}],
         "prompts": [{"question": "My ideal Sunday session", "answer": "25k, then brunch."}],
         "age": 29, "cardVersion": 7\(extra)}
        """
    }

    func testDecodesADiscoverCard() throws {
        let data = Data("[\(card(#", "distanceKm": 3, "superLikedMe": true, "superLikeNote": "Run?""#))]".utf8)
        let cards = try ProfileCard.list(from: data)
        XCTAssertEqual(cards.count, 1)
        let c = try XCTUnwrap(cards.first)
        XCTAssertEqual(c.id, id.lowercased(), "ids are compared lowercased")
        XCTAssertEqual(c.name, "Maya")
        XCTAssertEqual(c.age, 29)
        XCTAssertEqual(c.distanceKm, 3)
        XCTAssertTrue(c.superLikedMe)
        XCTAssertEqual(c.superLikeNote, "Run?")
        XCTAssertEqual(c.cardVersion, 7)
        XCTAssertEqual(c.sports.map(\.sport), ["trail", "yoga"])
        XCTAssertEqual(c.prompts.first?.answer, "25k, then brunch.")
        XCTAssertEqual(c.icebreaker?.kind, "joke")
        XCTAssertEqual(c.icebreaker?.punchline, "Because.")
        XCTAssertEqual(c.vitals?.chronotype, "Early bird")
        XCTAssertEqual(c.voiceIntro?.duration, 12.5)
        XCTAssertTrue(c.isShowable)
    }

    func testPhotoLinksPreferTheSignedURLAndSkipVideos() throws {
        let c = try XCTUnwrap(try ProfileCard.list(from: Data("[\(card())]".utf8)).first)
        let links = c.photoLinks(base: URL(string: "https://media.example"))
        XCTAssertEqual(links, [
            "https://media.example/u/x/photos/1.jpg?exp=1&sig=a",
            "https://media.example/u/x/photos/3.jpg"
        ])
        // Without a base (no signed link, no media URL): only the signed ones.
        XCTAssertEqual(c.photoLinks(base: nil), ["https://media.example/u/x/photos/1.jpg?exp=1&sig=a"])
    }

    func testMissingOptionalFieldsHaveDefaults() throws {
        let data = Data(#"[{"id": "abc", "name": "Sam", "media": [], "age": null}]"#.utf8)
        let c = try XCTUnwrap(try ProfileCard.list(from: data).first)
        XCTAssertEqual(c.bio, "")
        XCTAssertNil(c.age, "get_cards sends a null age for an unfinished sign-up")
        XCTAssertFalse(c.superLikedMe)
        XCTAssertEqual(c.cardVersion, 0)
        XCTAssertFalse(c.isShowable, "no age and no photo: never shown")
    }

    func testAMalformedIcebreakerOnlyHidesTheIcebreaker() throws {
        let data = Data("[\(card().replacingOccurrences(of: #""kind": "joke""#, with: #""kind": 3"#))]".utf8)
        let c = try XCTUnwrap(try ProfileCard.list(from: data).first)
        XCTAssertNil(c.icebreaker)
        XCTAssertEqual(c.name, "Maya")
    }

    func testOneBadCardNeverEmptiesTheList() throws {
        let data = Data("[\(card()), {\"name\": \"no id\"}]".utf8)
        XCTAssertEqual(try ProfileCard.list(from: data).count, 1)
    }

    func testDecodesLikedMe() throws {
        let data = Data("[\(card(#", "superLikedMe": false, "opener": {"kind": "text", "text": "Hi"}, "likedAt": "2026-09-28T10:00:00+00:00""#))]".utf8)
        let likes = try LikeCard.list(from: data)
        XCTAssertEqual(likes.first?.card.name, "Maya")
        XCTAssertEqual(likes.first?.likedAt, "2026-09-28T10:00:00+00:00")
    }

    func testDecodesMyMatches() throws {
        let data = Data("""
        [{"matchId": "AA11BB22-0000-4000-8000-000000000001", "matchedAt": "2026-09-28T10:00:00.123+00:00",
          "profile": \(card())}]
        """.utf8)
        let rows = try MatchRow.list(from: data)
        XCTAssertEqual(rows.first?.matchId, "aa11bb22-0000-4000-8000-000000000001")
        XCTAssertEqual(rows.first?.profile.id, id.lowercased())
    }

    // MARK: Deck merge

    func testMergeKeepsTheCardsOnScreenAndDropsStaleOnes() {
        let merged = DeckMerge.merge(current: ["a", "b", "c", "d", "e"], fresh: ["x", "b", "a", "y", "e"],
                                     keep: 4, exclude: [])
        // a and b stay on top (still available), c and d are gone (not in the fresh batch), then the
        // server's order.
        XCTAssertEqual(merged, ["a", "b", "x", "y", "e"])
    }

    func testMergeNeverShowsASwipeStillOnItsWay() {
        let merged = DeckMerge.merge(current: ["a", "b"], fresh: ["a", "b", "c"], keep: 4, exclude: ["a"])
        XCTAssertEqual(merged, ["b", "c"])
    }
}
