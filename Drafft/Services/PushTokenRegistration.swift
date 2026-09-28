import Foundation

/// Remembers which device token the server already holds for which account, so a return to the
/// app (which asks APNs for the token again, and gets the same one) doesn't write `push_tokens`
/// every time. The token is sent when it, the account or the APNs environment changed, and once a
/// day otherwise (the server's copy is refreshed if it was dropped). Forgotten on sign-out.
struct PushTokenRegistration {
    struct Record: Codable, Equatable {
        let account: UUID
        let token: String
        let environment: String
        let sentAt: Date
    }

    /// How long a sent token is trusted before it's sent again anyway.
    static let refreshInterval: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "pushTokenRegistration") {
        self.defaults = defaults
        self.key = key
    }

    private var record: Record? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    func needsSending(token: String, account: UUID, environment: String, now: Date = .now) -> Bool {
        guard let last = record, last.token == token, last.account == account,
              last.environment == environment else { return true }
        let age = now.timeIntervalSince(last.sentAt)
        return age < 0 || age >= Self.refreshInterval
    }

    func markSent(token: String, account: UUID, environment: String, at date: Date = .now) {
        let new = Record(account: account, token: token, environment: environment, sentAt: date)
        if let data = try? JSONEncoder().encode(new) { defaults.set(data, forKey: key) }
    }

    func forget() { defaults.removeObject(forKey: key) }
}
