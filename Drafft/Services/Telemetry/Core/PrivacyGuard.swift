import Foundation

/// The last check before anything goes to Sentry or PostHog. drafft holds sensitive data (gender, who
/// someone wants to meet, lifestyle answers: they can reveal orientation, health or beliefs, GDPR
/// article 9) and private conversations: none of it is ever a property, a tag or a log line.
///
/// - Property names on the `forbidden` list are dropped, whatever the event.
/// - Values are numbers, booleans, or short codes (`like`, `so.drafft.app.boost.5`, `discover`): a
///   string with spaces, capitals or punctuation is something a person typed and is dropped.
/// - Free text that must go (a log line, an error message) is `scrub`bed of emails, phone numbers,
///   ids, tokens and exact coordinates.
///
/// A dropped property is logged (and so reaches Sentry's logs); unit tests run every event through
/// `check`, so the mistake shows where it's made. The Android app applies the same rules.
enum PrivacyGuard {
    /// Never sent, whatever the event: the person's identity, sensitive data, content, location.
    static let forbidden: Set<String> = [
        // Identity and contact
        "name", "first_name", "last_name", "email", "phone", "phone_number", "birthday", "birthdate", "age",
        "address", "ip",
        // Sensitive data (article 9): gender and who someone wants to meet reveal orientation
        "gender", "identity", "interested_in", "show_me", "orientation", "pronouns",
        "lifestyle", "diet", "drinks", "smokes", "chronotype", "religion", "health",
        // What people write or record
        "bio", "message", "text", "note", "opener", "prompt", "answer", "caption", "report_text", "body",
        // Location
        "location", "latitude", "longitude", "lat", "lng", "lon", "coordinates", "neighborhood", "area", "city",
        // Another person
        "target", "target_id", "profile_id", "other_user", "match_id", "chat_id",
        // Secrets
        "token", "password", "code", "otp", "access_token", "refresh_token"
    ]

    /// The outcome of `check`: what may go, and what was dropped and why (`event.key: problem`).
    struct Checked: Equatable {
        var safe: [String: TelemetryValue]
        var problems: [String]
    }

    /// The properties that may go: allowed names, safe values. A dropped one is logged.
    static func properties(_ event: String, _ properties: TelemetryProperties) -> [String: TelemetryValue] {
        let checked = check(event, properties)
        for problem in checked.problems {
            Telemetry.log(.warning, "property dropped: \(problem)")
        }
        return checked.safe
    }

    /// `properties` without the logging: what passes and what doesn't (unit tests).
    static func check(_ event: String, _ properties: TelemetryProperties) -> Checked {
        var out = Checked(safe: [:], problems: [])
        for (key, raw) in properties {
            guard let raw else { continue }
            let value = allowed(raw.telemetryValue)
            let problem: String? = if forbidden.contains(key.lowercased()) {
                "forbidden property"
            } else if !isCode(key) {
                "property name isn't snake_case"
            } else if value == nil {
                "value isn't a number, a boolean or a short code"
            } else {
                nil
            }
            if let problem {
                out.problems.append("\(event).\(key): \(problem)")
            } else if let value {
                out.safe[key] = value
            }
        }
        return out
    }

    /// A short code (`daily_like_limit`), not words.
    static func isCode(_ text: String) -> Bool { matches(slug, text) }

    private static func allowed(_ value: TelemetryValue) -> TelemetryValue? {
        switch value {
        case .bool, .int: value
        case let .double(d): d.isFinite ? value : nil
        case let .string(s): isCode(s) ? value : nil
        case let .strings(list): list.count <= 20 && list.allSatisfy(isCode) ? value : nil
        }
    }

    // MARK: Free text

    private static let slug = regex(#"^[a-z0-9][a-z0-9_.:\-]{0,79}\z"#)
    private static let email = regex(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#)
    /// International (+33 6 12 34 56 78) and national (06 12 34 56 78) forms; not timestamps or ids.
    private static let phone = regex(#"\+\d[\d .()-]{6,18}\d|\b0\d(?:[ .-]?\d{2}){4}\b"#)
    private static let bearer = regex(#"(?i)(bearer\s+|apikey[=:]\s*|token[=:]\s*)[A-Za-z0-9._-]+"#)
    private static let jwt = regex(#"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#)
    private static let coordinates = regex(#"-?\d{1,3}\.\d{3,}\s*,\s*-?\d{1,3}\.\d{3,}"#)
    private static let uuid = regex(#"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#)
    private static let query = regex(#"\?[^\s]*"#)

    /// Free text with what identifies someone taken out. Query strings go too (they carry ids and filters).
    static func scrub(_ text: String) -> String {
        var out = replace(jwt, in: text, with: "[token]")
        out = replace(bearer, in: out, with: "$1[token]")
        out = replace(email, in: out, with: "[email]")
        // Another person's id is theirs: the account's own goes with the report as its user.
        out = replace(uuid, in: out, with: "[id]")
        out = replace(coordinates, in: out, with: "[coordinates]")
        out = replace(phone, in: out, with: "[phone]")
        return out.count > 2000 ? String(out.prefix(2000)) : out
    }

    /// A URL or path without its query (`rest/v1/profiles?id=eq.<id>` → `rest/v1/profiles`).
    static func path(_ url: String) -> String { replace(query, in: url, with: "") }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            fatalError("PrivacyGuard: invalid pattern \(pattern)")
        }
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
