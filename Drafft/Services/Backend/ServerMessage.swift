import Foundation

/// What people read when the server turns something down. Database functions put a stable code in
/// `hint` (`private.fail`), Edge Functions in `code`; the known ones get their own words, anything
/// else (a constraint without a hint, an unexpected reply) a generic line, never the raw reply.
enum ServerMessage {
    static var generic: String { L("Something went wrong. Try again in a moment.") }

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

    /// A code is one word (`media_limit`); anything with a space is a sentence from the server.
    static func isCode(_ message: String) -> Bool { !message.isEmpty && !message.contains(" ") }

    // swiftlint:disable:next cyclomatic_complexity
    static func text(forCode code: String) -> String? {
        switch code {
        // complete_onboarding
        case "name_required": L("Add your first name.")
        case "underage": L("You need to be 18 or older to use drafft.")
        case "gender_required": L("Pick the one that fits you best.")
        case "sport_required": L("Add at least one sport.")
        case "photo_required": L("Add at least one photo.")
        case "birthdate_locked": L("Your birthday can't be changed.")
        case "email_unconfirmed": L("Confirm your email first.")
        case "phone_required": L("Verify your phone number first.")
        // Photos and videos (add_profile_media, request_media_review, media-upload-url)
        case "media_limit": L("You've reached the photo limit. Remove one, then try again.")
        case "not_reviewable": L("This photo has already been reviewed.")
        case "too_large": L("This file is too large.")
        case "unsupported_type": L("This file type isn't supported.")
        // Account state
        case "moderated": L("Your account is on hold.")
        case "paused": L("Your profile is paused")
        case "onboarding_required": L("Finish your profile first.")
        // Discover and safety
        case "not_eligible": L("This profile isn't available.")
        case "report_limit": L("You've sent several reports already. Try again later.")
        // Sessions (propose_session, counter_session, respond_session, cancel_session)
        case "invalid_options": L("Pick 1 to 3 times that haven't passed.")
        case "invalid_pick": L("Pick one of the times offered.")
        case "cannot_respond", "cannot_counter": L("This invite has already been answered.")
        case "cannot_cancel": L("This session is already closed.")
        default: nil
        }
    }
}
