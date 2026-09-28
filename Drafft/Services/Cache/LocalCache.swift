import Foundation
import GRDB

/// The last known state of each account, on this iPhone (SQLite through GRDB): shown at launch
/// before the network answers, then replaced by the server's (stale-while-revalidate). A cache
/// only: the server is the truth, and anything here can be dropped at any time.
///
/// One database file per account, named after its id: two people on one iPhone never see each
/// other's data, and signing out or deleting the account removes the whole file.
///
/// Entries are the server's own payloads (JSON), by kind: decoding them again goes through the same
/// code as a fresh read, so the cache never has a shape of its own to keep in step.
final class LocalCache: Sendable {
    /// What's kept. Raw values are stored: never rename one.
    enum Kind: String, Sendable, CaseIterable {
        /// The account's own profile row, with its sports, prompts and media.
        case profile
        /// Matches (`my_matches`: the conversation list).
        case matches
        /// Upcoming and past sessions.
        case sessions
        /// The last batch of Discover cards.
        case deck
        /// Who liked the account (`liked_me`).
        case likes
    }

    /// A payload and when it was saved.
    struct Entry: Sendable, Equatable {
        let data: Data
        let savedAt: Date
    }

    let account: UUID
    private let db: DatabaseQueue

    /// The cache of `account` in `directory` (created if needed). Throws if the file can't be opened;
    /// callers carry on without a cache then.
    init(account: UUID, directory: URL = LocalCache.defaultDirectory) throws {
        self.account = account
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = Self.fileURL(account: account, directory: directory)
        var config = Configuration()
        config.label = "LocalCache"
        db = try DatabaseQueue(path: url.path, configuration: config)
        try Self.migrator.migrate(db)
        // Not backed up to iCloud: it's rebuilt from the server anyway.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var file = url
        try? file.setResourceValues(values)
    }

    /// Application Support/LocalCache (kept across launches, not shown in Files, not backed up).
    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("LocalCache", isDirectory: true)
    }

    /// One file per account. The id is lowercased so a key never depends on how it was printed.
    static func fileURL(account: UUID, directory: URL = defaultDirectory) -> URL {
        directory.appendingPathComponent("\(account.uuidString.lowercased()).sqlite")
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "entry") { t in
                t.column("kind", .text).notNull().primaryKey()
                t.column("payload", .blob).notNull()
                t.column("savedAt", .double).notNull()
            }
        }
        return migrator
    }

    // MARK: Reading and writing

    func entry(_ kind: Kind) -> Entry? {
        try? db.read { db in
            try Row.fetchOne(db, sql: "SELECT payload, savedAt FROM entry WHERE kind = ?", arguments: [kind.rawValue])
                .map { Entry(data: $0["payload"], savedAt: Date(timeIntervalSince1970: $0["savedAt"])) }
        }
    }

    func save(_ data: Data, as kind: Kind, at date: Date = .now) {
        try? db.write { db in
            try db.execute(sql: """
                INSERT INTO entry (kind, payload, savedAt) VALUES (?, ?, ?)
                ON CONFLICT(kind) DO UPDATE SET payload = excluded.payload, savedAt = excluded.savedAt
                """, arguments: [kind.rawValue, data, date.timeIntervalSince1970])
        }
    }

    func remove(_ kind: Kind) {
        try? db.write { db in try db.execute(sql: "DELETE FROM entry WHERE kind = ?", arguments: [kind.rawValue]) }
    }

    // MARK: Accounts

    /// Removes an account's cache from the phone (sign-out, account deletion). Its open connections
    /// should be released first (drop the `LocalCache`).
    static func erase(account: UUID, directory: URL = defaultDirectory) {
        let url = fileURL(account: account, directory: directory)
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    /// Removes every account's cache (used when the signed-in account can't be told).
    static func eraseAll(directory: URL = defaultDirectory) {
        try? FileManager.default.removeItem(at: directory)
    }
}
