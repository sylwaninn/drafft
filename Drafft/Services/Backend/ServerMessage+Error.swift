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
}
