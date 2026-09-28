import XCTest

final class SessionLedgerTests: XCTestCase {
    private let match = UUID()
    private let me = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func row(_ id: UUID = UUID(), status: SessionRecord.Status = .pending, options: [Date]? = nil,
                     chosen: Date? = nil, version: TimeInterval = 0) -> SessionRecord {
        SessionRecord(id: id, matchID: match, proposerID: me, sportID: "running",
                      options: options ?? [now.addingTimeInterval(86_400), now.addingTimeInterval(2 * 86_400)],
                      chosenAt: chosen, status: status, updatedAt: now.addingTimeInterval(version))
    }

    // MARK: Decoding

    func testDecodesAnUpcomingSessionWithItsPartner() throws {
        let json = """
        [{"id":"8f7c1c2e-1b1a-4c55-9a55-0d7c5e0b8a11","match_id":"2b8e3f4a-5c6d-4e7f-8a9b-0c1d2e3f4a5b",
          "proposer_id":"3c9f4a5b-6d7e-4f8a-9b0c-1d2e3f4a5b6c","sport_id":"trail",
          "options":["2026-10-25T07:30:00+01:00","2026-10-26T08:00:00.123456+00:00"],
          "chosen_at":null,"title":"","note":"","tags":["Easy pace"],"discovery":"iTeach","status":"pending",
          "replaces_id":null,"created_at":"2026-09-28T10:00:00.5+00:00","updated_at":"2026-09-28T10:00:00.654321+00:00",
          "with":{"id":"4d0a5b6c-7e8f-4a9b-0c1d-2e3f4a5b6c7d","name":"Maya",
                  "photo":{"key":"u/x/1.jpg","url":"https://media.example/u/x/1.jpg?sig=1"}}}]
        """
        let rows = try JSONDecoder().decode([SessionRecord].self, from: Data(json.utf8))
        let r = try XCTUnwrap(rows.first)
        XCTAssertEqual(r.sportID, "trail")
        XCTAssertEqual(r.status, .pending)
        XCTAssertEqual(r.discovery, "iTeach")
        XCTAssertEqual(r.tags, ["Easy pace"])
        XCTAssertEqual(r.options.first, try ServerDate.parse("2026-10-25T06:30:00Z"))
        XCTAssertEqual(r.options.last?.timeIntervalSince1970 ?? 0,
                       try ServerDate.parse("2026-10-26T08:00:00Z").timeIntervalSince1970 + 0.123, accuracy: 0.001)
        XCTAssertEqual(r.partner?.name, "Maya")
        XCTAssertEqual(r.partner?.photo, "https://media.example/u/x/1.jpg?sig=1")
    }

    func testDecodesAPlainRowWithoutPartner() throws {
        let json = """
        {"id":"8f7c1c2e-1b1a-4c55-9a55-0d7c5e0b8a11","match_id":"2b8e3f4a-5c6d-4e7f-8a9b-0c1d2e3f4a5b",
         "proposer_id":"3c9f4a5b-6d7e-4f8a-9b0c-1d2e3f4a5b6c","sport_id":"padel","options":["2026-10-25T07:30:00+00:00"],
         "chosen_at":"2026-10-25T07:30:00+00:00","title":"Doubles?","note":"","tags":[],"discovery":null,
         "status":"accepted","replaces_id":null,"updated_at":"2026-09-28T10:00:00+00:00"}
        """
        let r = try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.status, .accepted)
        XCTAssertEqual(r.chosenAt, r.options.first)
        XCTAssertNil(r.partner)
        XCTAssertNil(r.discovery)
    }

    func testSentTimesRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(try ServerDate.parse(ServerDate.string(date)), date)
    }

    // MARK: Merging

    func testNewerRowWinsAndOlderReplyIsIgnored() {
        var ledger = SessionLedger()
        let id = UUID()
        ledger.merge([row(id, status: .accepted, chosen: now.addingTimeInterval(86_400), version: 10)])
        ledger.merge([row(id, status: .pending, version: 5)])
        XCTAssertEqual(ledger.visible[id]?.status, .accepted, "an older read never overwrites a newer one")
        ledger.merge([row(id, status: .cancelled, version: 20)])
        XCTAssertEqual(ledger.visible[id]?.status, .cancelled)
    }

    func testPartnerIsKeptWhenARowComesWithoutIt() {
        var ledger = SessionLedger()
        let id = UUID()
        var first = row(id)
        first.partner = .init(id: UUID(), name: "Maya", photo: nil)
        ledger.merge([first])
        ledger.merge([row(id, status: .accepted, chosen: first.options[0], version: 1)])
        XCTAssertEqual(ledger.visible[id]?.partner?.name, "Maya")
    }

    // MARK: Optimistic changes

    func testAcceptShowsAtOnceThenSettles() {
        var ledger = SessionLedger()
        let id = UUID()
        let base = row(id)
        ledger.merge([base])
        let token = ledger.begin(.respond(id, accept: true, pick: base.options[1]))
        XCTAssertEqual(ledger.visible[id]?.status, .accepted)
        XCTAssertEqual(ledger.visible[id]?.chosenAt, base.options[1])
        XCTAssertTrue(ledger.isBusy(id))
        var server = base
        server.status = .accepted
        server.chosenAt = base.options[1]
        server.updatedAt = now.addingTimeInterval(1)
        ledger.settle(token, with: [server])
        XCTAssertFalse(ledger.isBusy(id))
        XCTAssertEqual(ledger.visible[id], server)
    }

    func testRefusedChangeIsRolledBackToTheLatestServerState() {
        var ledger = SessionLedger()
        let id = UUID()
        ledger.merge([row(id)])
        let token = ledger.begin(.cancel(id))
        XCTAssertEqual(ledger.visible[id]?.status, .cancelled)
        // Meanwhile Realtime brought the other person's answer.
        ledger.merge([row(id, status: .declined, version: 3)])
        ledger.fail(token)
        XCTAssertEqual(ledger.visible[id]?.status, .declined, "rolled back to the server, not to a stale snapshot")
    }

    func testCounterMarksTheOldOneAndAddsTheNew() {
        var ledger = SessionLedger()
        let old = UUID(), new = UUID()
        ledger.merge([row(old)])
        let token = ledger.begin(.counter(old, row(new)))
        XCTAssertEqual(ledger.visible[old]?.status, .countered)
        XCTAssertEqual(ledger.visible[new]?.status, .pending)
        ledger.fail(token)
        XCTAssertEqual(ledger.visible[old]?.status, .pending)
        XCTAssertNil(ledger.visible[new])
    }

    func testAChangeOnAClosedSessionShowsNothing() {
        var ledger = SessionLedger()
        let id = UUID()
        ledger.merge([row(id, status: .declined)])
        ledger.begin(.cancel(id))
        ledger.begin(.respond(id, accept: true, pick: nil))
        XCTAssertEqual(ledger.visible[id]?.status, .declined)
    }

    func testProposalIsReplacedByTheServerRow() {
        var ledger = SessionLedger()
        let local = row()
        let token = ledger.begin(.propose(local))
        XCTAssertEqual(ledger.upcoming(at: now).map(\.id), [local.id])
        let saved = row(version: 1)
        ledger.settle(token, with: [saved])
        XCTAssertNil(ledger.visible[local.id])
        XCTAssertEqual(ledger.visible[saved.id], saved)
    }

    // MARK: Upcoming

    func testUpcomingIsOpenAndNotPassedSoonestFirst() {
        var ledger = SessionLedger()
        let later = row(options: [now.addingTimeInterval(3 * 86_400)])
        let sooner = row(status: .accepted, options: [now.addingTimeInterval(3600)], chosen: now.addingTimeInterval(3600))
        let justStarted = row(status: .accepted, options: [now.addingTimeInterval(-3600)], chosen: now.addingTimeInterval(-3600))
        let passed = row(status: .accepted, options: [now.addingTimeInterval(-3 * 3600)], chosen: now.addingTimeInterval(-3 * 3600))
        let cancelled = row(status: .cancelled)
        ledger.merge([later, sooner, justStarted, passed, cancelled])
        XCTAssertEqual(ledger.upcoming(at: now).map(\.id), [justStarted.id, sooner.id, later.id])
    }

    func testRemoveForgetsGoneSessions() {
        var ledger = SessionLedger()
        let a = row(), b = row()
        ledger.merge([a, b])
        ledger.remove([a.id])
        XCTAssertNil(ledger.visible[a.id])
        XCTAssertNotNil(ledger.visible[b.id])
        ledger.reset()
        XCTAssertTrue(ledger.visible.isEmpty)
    }
}
