import Foundation
import RevenueCat
import Supabase

/// The app's errors, read for `Telemetry` (see `ErrorKind`): only what needs a fix alerts in Sentry.
/// Installed at launch by `TelemetrySession.start`.
struct AppErrorClassifier: ErrorClassifier {
    // swiftlint:disable:next cyclomatic_complexity
    func kind(of error: Error) -> ErrorKind {
        if let basic = ErrorKind.basic(error) { return basic }
        if error.isSignedOut { return .signedOut }
        switch error {
        case let error as Backend.BackendError:
            if case let .http(status, message) = error { return ErrorKind.http(status: status, message: message) }
            return .signedOut
        case is Backend.EmailAlreadyRegistered, is ChatService.SendRefused:
            return .refused
        case let error as ProfileSync.SyncError:
            // The server's refusal, or a step that failed with its own reason (a photo, the voice intro).
            if case .notLoaded = error { return .refused }
            if case .refused = error { return .refused }
            return .unexpected
        case let error as VerificationError:
            switch error {
            case .network: return .offline
            // Nothing the person did: the SMS or the line check failed on the way.
            case .sendFailed, .checkUnavailable: return .server
            default: return .refused
            }
        // Supabase Auth's refusals (a wrong password, an expired code): the screen says why.
        case let error as AuthError:
            if case let .api(_, _, _, response) = error {
                if response.statusCode == 429 { return .rateLimited }
                if response.statusCode >= 500 { return .server }
            }
            return .refused
        case let error as MediaUploadError:
            switch error {
            case .rejected: return .refused
            case .ticketExpired: return .signedOut
            case let .http(status): return ErrorKind.http(status: status, message: "")
            }
        case Store.StoreError.notLinked:
            return .offline
        default:
            break
        }
        if let store = error as? RevenueCat.ErrorCode {
            // RevenueCat or the App Store unreachable is the phone's connection, not a bug.
            if store == .networkError || store == .offlineConnectionError { return .offline }
            if store == .purchaseCancelledError { return .cancelled }
            // The store's own outcomes are only ever the purchase's. Any other code is unexpected here
            // (`link`, `load_offerings`, `restore`); the purchase itself says when the store may have
            // charged without confirming (`Store.purchase`).
            return Store.PurchaseProblem(code: store) == nil ? .unexpected : .storeDeclined
        }
        if ServerMessage.code(of: error) != nil { return .refused }
        // An SDK's error around the real cause (Stream's client errors): offline when that cause is.
        if let underlying = Self.underlying(error), let basic = ErrorKind.basic(underlying) { return basic }
        return .unexpected
    }

    func code(of error: Error) -> String? {
        switch error {
        case is Backend.EmailAlreadyRegistered: return "email_taken"
        // Supabase Auth's own codes: `invalid_credentials`, `otp_expired`, `weak_password`...
        // A refusal from the database behind Auth carries its own code in the hint (`email_taken` for an
        // address a banned account used), the one the screen reads (`AuthProblem`).
        case let error as AuthError: return AuthProblem.hint(of: error) ?? error.errorCode.rawValue
        case let error as ProfileSync.SyncError:
            if case let .refused(code) = error { return code }
            return nil
        case let error as VerificationError: return String(describing: error).snakeCased
        case let error as Store.StoreError: return String(describing: error).snakeCased
        default: return ServerMessage.code(of: error)
        }
    }

    /// The error an SDK's error wraps: Foundation's `NSUnderlyingErrorKey`, or an `underlyingError`.
    private static func underlying(_ error: Error) -> Error? {
        if let inner = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error { return inner }
        return Mirror(reflecting: error).children.first { $0.label == "underlyingError" }?.value as? Error
    }
}
