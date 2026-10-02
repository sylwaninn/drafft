import AuthenticationServices
import Foundation

/// What kind of failure an error is, for `Telemetry.unexpected`. Only the `reportable` kinds become
/// Sentry events (and can alert someone): a phone going offline or the server refusing with a reason the
/// person reads on screen is the app working as it should.
enum ErrorKind: String, Sendable, CaseIterable {
    case cancelled
    case offline
    case signedOut = "signed_out"
    /// The server said no with a code the app explains (`daily_like_limit`, `paused`...).
    case refused
    case rateLimited = "rate_limited"
    /// The store's own outcomes (waiting for approval, not allowed, already owned, not charged).
    case storeDeclined = "store_declined"
    /// A 4xx without a code the app knows: the app and the server disagree on something.
    case clientContract = "client_contract"
    /// A 5xx: the server failed.
    case server
    /// A purchase the App Store may have charged without RevenueCat confirming it.
    case storeUnconfirmed = "store_unconfirmed"
    case unexpected

    var reportable: Bool {
        switch self {
        case .clientContract, .server, .storeUnconfirmed, .unexpected: true
        case .cancelled, .offline, .signedOut, .refused, .rateLimited, .storeDeclined: false
        }
    }

    /// A response that wasn't 2xx, from its status and the server's code or message.
    static func http(status: Int, message: String) -> ErrorKind {
        if status == 429 { return .rateLimited }
        if status >= 500 { return .server }
        // An expired or revoked token: the session refresh and the sign-out handle it.
        if status == 401 { return .signedOut }
        // A code (one word) is a refusal the server meant (`not_found`, `already_swiped`), whether or
        // not the app has words for it. A sentence is the database failing.
        return PrivacyGuard.isCode(message.lowercased()) ? .refused : .clientContract
    }

    /// What every error can tell without knowing the app's types: cancelled, or never reached a server.
    /// A URL error that isn't the connection (a certificate, an unsupported URL, a response that can't
    /// be read) is a bug or an attack, not a phone going offline.
    static func basic(_ error: Error) -> ErrorKind? {
        if error is CancellationError { return .cancelled }
        if let url = error as? URLError { return connection(url.code) }
        let ns = error as NSError
        switch ns.domain {
        case NSURLErrorDomain: return connection(URLError.Code(rawValue: ns.code))
        // The person closed a system sheet (a file picker, Sign in with Apple).
        case NSCocoaErrorDomain: return ns.code == NSUserCancelledError ? .cancelled : nil
        case ASAuthorizationError.errorDomain: return ns.code == ASAuthorizationError.canceled.rawValue ? .cancelled : nil
        default: return nil
        }
    }

    /// Only the connection itself is offline.
    private static func connection(_ code: URLError.Code) -> ErrorKind {
        switch code {
        case .cancelled: .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed: .offline
        default: .unexpected
        }
    }
}

/// Reads the app's errors for `Telemetry`: their kind, and the server's code when there is one. The
/// app installs its own (`AppErrorClassifier`, which knows Backend, Store, ProfileSync...); until then,
/// and in unit tests, `BasicErrorClassifier` only tells cancelled and offline apart.
protocol ErrorClassifier: Sendable {
    func kind(of error: Error) -> ErrorKind
    /// The server's (or the SDK's) stable code for this failure, if any: `daily_like_limit`, `otp_expired`.
    func code(of error: Error) -> String?
}

struct BasicErrorClassifier: ErrorClassifier {
    func kind(of error: Error) -> ErrorKind { ErrorKind.basic(error) ?? .unexpected }
    func code(of error: Error) -> String? { nil }
}
