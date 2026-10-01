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

    /// An action that failed, in words: the known refusal's, the connection's only when the request
    /// never got through, else the generic line. Never the server's reply.
    static func failure(for error: Error) -> String {
        switch error {
        case is URLError: L("Couldn't connect. Check your connection and try again.")
        case let error as Backend.BackendError: error.errorDescription ?? generic
        default: text(for: error) ?? generic
        }
    }
}
