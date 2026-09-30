import Foundation

/// The terms and the consent to sensitive data, recorded on the server (`accept_terms`): the version
/// of the terms accepted and when, and when the consent was given. Gender and the genders someone
/// wants to see can reveal their sexual orientation, lifestyle answers their health or beliefs: drafft
/// uses them on explicit consent, which it must be able to show. Sign-up records both on the ground
/// rules step; an onboarded account missing either one for the current version is asked at each open
/// until it accepts (`TermsConsentView`). `complete_onboarding` refuses a sign-up without them
/// (`terms_required`). Foundation only, so the rules are unit-tested; the call to the server is in
/// TermsConsent+Accept.swift.
enum TermsConsent {
    /// The version of the terms on getdrafft.com the app shows, an ISO date (`yyyy-MM-dd`, the shape
    /// the server accepts). A newer one asks everyone again.
    static let version = "2026-09-29"

    /// The one version rule: a well-formed version on or after the one this build shows. A newer
    /// one (accepted from a newer build) counts, so an older build doesn't ask again in a loop. ISO
    /// dates compare as text, which is why a malformed one never counts.
    static func isCurrent(_ accepted: String?) -> Bool {
        guard let accepted, isWellFormed(accepted) else { return false }
        return accepted >= version
    }

    /// `yyyy-MM-dd`, digits only: the shape that makes the text comparison a date comparison.
    static func isWellFormed(_ version: String) -> Bool {
        version.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
    }

    /// What the profile holds once `accept_terms` has run: the version and when, always together,
    /// and when the consent was given.
    struct Record: Equatable, Sendable {
        let version: String
        let acceptedAt: String
        let sensitiveConsentAt: String?

        /// Nil when the terms were never accepted (no version or no date).
        init?(version: String?, acceptedAt: String?, sensitiveConsentAt: String?) {
            guard let version, let acceptedAt else { return nil }
            self.version = version
            self.acceptedAt = acceptedAt
            self.sensitiveConsentAt = sensitiveConsentAt
        }
    }

    /// Whether an account still has to accept: nothing on record, terms older than this version, or
    /// no consent to sensitive data.
    static func isNeeded(_ record: Record?) -> Bool {
        guard let record else { return true }
        return !isCurrent(record.version) || record.sensitiveConsentAt == nil
    }

    /// Whether the app asks for the consent (`TermsConsentView`).
    enum Gate: Equatable, Sendable {
        /// Not known yet: no read, a failed one, or a backend without the columns. Nothing is asked
        /// meanwhile; a failed read is logged and retried (`AppModel.refreshAccount`).
        case unknown
        /// A fresh read found it missing. Only a read from the server sets it, never the cache.
        case required
        /// Nothing to ask: on record for this version, or a sign-up still under way (it records the
        /// consent itself, and `complete_onboarding` checks it). A cached copy that says so is
        /// trusted: the consent is only withdrawn by deleting the account.
        case accepted
    }

    /// The columns of the profile row the gate reads, from the row's bytes (`ProfileSync` hands over
    /// a fresh read or the cached copy). A key that's absent (a backend without the columns, a copy
    /// cached before this build) is told apart from a null one (read, nothing on record).
    struct Columns: Decodable {
        let onboarded: Bool
        /// The row carries the three columns `accept_terms` fills.
        let carriesConsent: Bool
        let record: Record?

        private enum CodingKeys: String, CodingKey {
            case onboardedAt = "onboarded_at"
            case termsVersion = "terms_version"
            case termsAcceptedAt = "terms_accepted_at"
            case sensitiveConsentAt = "sensitive_consent_at"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            onboarded = try c.decodeIfPresent(String.self, forKey: .onboardedAt) != nil
            carriesConsent = [CodingKeys.termsVersion, .termsAcceptedAt, .sensitiveConsentAt].allSatisfy(c.contains)
            record = Record(
                version: try c.decodeIfPresent(String.self, forKey: .termsVersion),
                acceptedAt: try c.decodeIfPresent(String.self, forKey: .termsAcceptedAt),
                sensitiveConsentAt: try c.decodeIfPresent(String.self, forKey: .sensitiveConsentAt))
        }

        var gate: Gate {
            guard onboarded else { return .accepted }
            guard carriesConsent else { return .unknown }
            return isNeeded(record) ? .required : .accepted
        }
    }

    /// The gate a profile row sets (a JSON array of one, as PostgREST sends it). Unknown when the
    /// bytes aren't a row.
    static func gate(fromProfileRow data: Data) -> Gate {
        (try? JSONDecoder().decode([Columns].self, from: data))?.first?.gate ?? .unknown
    }

    /// What the app does when `accept_terms` fails.
    enum Failure: Equatable {
        /// No session, or no profile behind it (an account deleted): nothing this session can
        /// record, so it ends, and the welcome screen says the person was logged out.
        case signOut
        case message(String)
    }

    /// `code`: the server's refusal (its `hint`), nil without one. `offline`: the request never
    /// reached the server.
    static func failure(code: String?, offline: Bool) -> Failure {
        switch code {
        case "unauthenticated", "not_found": .signOut
        // Newer terms are on record (a newer build accepted them): only an update shows them.
        case "invalid_terms_version": .message(L("drafft has newer terms. Update the app to continue."))
        case let code?: .message(ServerMessage.text(forCode: code) ?? ServerMessage.generic)
        case nil where offline: .message(L("Your consent couldn't be saved. Check your connection and try again."))
        // A reply without a code: a server error, or a backend without accept_terms.
        case nil: .message(ServerMessage.generic)
        }
    }
}

/// The two boxes of the consent step, unticked until the person ticks them. Sign-up and
/// `TermsConsentView` share it through `ConsentChecks`.
struct ConsentDraft: Equatable {
    var terms = false
    var sensitiveData = false

    /// Both are required: drafft can't work without the gender.
    var isComplete: Bool { terms && sensitiveData }

    /// Both ticked.
    static let accepted = ConsentDraft(terms: true, sensitiveData: true)

    /// A resumed sign-up: ticked again only if the version recorded with the consent is current.
    static func restored(recordedVersion: String?) -> ConsentDraft {
        TermsConsent.isCurrent(recordedVersion) ? .accepted : ConsentDraft()
    }
}
