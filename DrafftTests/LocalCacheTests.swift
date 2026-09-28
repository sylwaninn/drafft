import XCTest

final class LocalCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LocalCacheTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSavedPayloadIsReadBack() throws {
        let cache = try LocalCache(account: UUID(), directory: directory)
        let data = Data(#"[{"name":"Alex"}]"#.utf8)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        cache.save(data, as: .profile, at: date)
        XCTAssertEqual(cache.entry(.profile), LocalCache.Entry(data: data, savedAt: date))
        XCTAssertNil(cache.entry(.matches))
    }

    func testNewerPayloadReplacesTheOldOne() throws {
        let cache = try LocalCache(account: UUID(), directory: directory)
        cache.save(Data("old".utf8), as: .deck)
        cache.save(Data("new".utf8), as: .deck)
        XCTAssertEqual(cache.entry(.deck)?.data, Data("new".utf8))
    }

    func testSurvivesReopening() throws {
        let account = UUID()
        try LocalCache(account: account, directory: directory).save(Data("kept".utf8), as: .sessions)
        XCTAssertEqual(try LocalCache(account: account, directory: directory).entry(.sessions)?.data, Data("kept".utf8))
    }

    /// Two accounts on one iPhone never read each other's cache.
    func testAccountsAreKeptApart() throws {
        let alex = try LocalCache(account: UUID(), directory: directory)
        let sam = try LocalCache(account: UUID(), directory: directory)
        alex.save(Data("alex".utf8), as: .profile)
        XCTAssertNil(sam.entry(.profile))
        XCTAssertNotEqual(LocalCache.fileURL(account: alex.account, directory: directory),
                          LocalCache.fileURL(account: sam.account, directory: directory))
    }

    /// The key doesn't depend on how the id was written.
    func testKeyIgnoresCase() throws {
        let id = UUID()
        let upper = try XCTUnwrap(UUID(uuidString: id.uuidString.uppercased()))
        let lower = try XCTUnwrap(UUID(uuidString: id.uuidString.lowercased()))
        XCTAssertEqual(LocalCache.fileURL(account: upper, directory: directory),
                       LocalCache.fileURL(account: lower, directory: directory))
    }

    /// Sign-out and account deletion leave nothing of the account behind, and only that account.
    func testEraseRemovesOnlyThatAccount() throws {
        let gone = UUID(), kept = UUID()
        do {
            try LocalCache(account: gone, directory: directory).save(Data("x".utf8), as: .profile)
            try LocalCache(account: kept, directory: directory).save(Data("y".utf8), as: .profile)
        }
        LocalCache.erase(account: gone, directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: LocalCache.fileURL(account: gone, directory: directory).path))
        XCTAssertNil(try LocalCache(account: gone, directory: directory).entry(.profile))
        XCTAssertEqual(try LocalCache(account: kept, directory: directory).entry(.profile)?.data, Data("y".utf8))
    }
}
