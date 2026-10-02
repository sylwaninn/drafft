import Foundation

extension ServerMessage {
    /// The server's code for a refusal, if it gave one.
    static func code(of error: Error) -> String? {
        switch error {
        case Backend.BackendError.http(_, let message) where isCode(message): message
        case MediaUploadError.rejected(let code): code
        default: nil
        }
    }

    /// The words for a refusal the app knows, or nil (not a refusal, or a code it doesn't know).
    static func text(for error: Error) -> String? { code(of: error).flatMap(text(forCode:)) }

    /// What to say when a call fails: the refusal's own words when the app knows its code, the logged-out
    /// line when the session is gone, `offline` when the request never got through, else `fallback`.
    static func text(for error: Error, offline: String, fallback: String = generic) -> String {
        // A profile save's own reasons (a photo that didn't go, a profile that wasn't read).
        if let error = error as? ProfileSync.SyncError { return error.errorDescription ?? fallback }
        if let text = text(for: error) { return text }
        if case Backend.BackendError.signedOut = error { return Backend.BackendError.signedOut.errorDescription ?? fallback }
        return isOffline(error) ? offline : fallback
    }

    /// An action that failed, in words: the known refusal's, the connection's only when the request
    /// never got through, else the generic line. Never the server's reply.
    static func failure(for error: Error) -> String {
        if isOffline(error) { return L("Couldn't connect. Check your connection and try again.") }
        if let error = error as? Backend.BackendError { return error.errorDescription ?? generic }
        return text(for: error) ?? generic
    }
}

extension Error {
    /// The session is gone: no token on the device, or an edge function's 401 `unauthenticated`.
    var isSignedOut: Bool {
        if let error = self as? Backend.BackendError, case .signedOut = error { return true }
        return ServerMessage.code(of: self) == "unauthenticated"
    }
}
