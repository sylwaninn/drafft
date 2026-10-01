import Foundation

/// What people read when the server turns something down. Database functions put a stable code in
/// `hint` (`private.fail`), Edge Functions in `code`; the known ones get their own words, anything
/// else (a constraint without a hint, an unexpected reply) a generic line, never the raw reply.
/// Foundation only, so the words are unit-tested; reading the code out of an error is in
/// ServerMessage+Error.swift.
enum ServerMessage {
    static var generic: String { L("Something went wrong. Try again in a moment.") }

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
        // The first photo isn't approved yet, was refused, or shows no face (server check).
        case "portrait_required": L("Put a clear photo of your face first.")
        case "birthdate_locked": L("Your birthday can't be changed.")
        case "email_unconfirmed": L("Confirm your email first.")
        case "phone_required": L("Verify your phone number first.")
        // complete_onboarding without accept_terms, and accept_terms without the consent (the app
        // always sends it, so only another client gets sensitive_consent_required)
        case "terms_required": L("Accept the terms and give your consent to continue.")
        case "sensitive_consent_required": L("drafft needs your consent to use your gender. Tick it to continue.")
        // Photos and videos (add_profile_media, request_media_review, media-upload-url)
        case "media_limit": L("You've reached the photo limit. Remove one, then try again.")
        case "not_reviewable": L("This photo has already been reviewed.")
        case "too_large": L("This file is too large.")
        case "unsupported_type": L("This file type isn't supported.")
        // Account state
        case "moderated": L("Your account is on hold.")
        case "paused": L("Your profile is paused")
        case "onboarding_required": L("Finish your profile first.")
        // An edge function without a valid session (it expired, or was ended on another device).
        case "unauthenticated": L("You've been logged out. Log in again to continue.")
        // Discover and safety
        case "not_eligible", "invalid_target": L("This profile isn't available.")
        case "location_required": L("Share your location to see people nearby.")
        case "daily_like_limit": L("You're out of likes for today.")
        case "no_super_likes": L("You're out of super likes.")
        case "cannot_undo": L("This swipe can't be undone any more.")
        case "no_boost": L("No boost left, or one is already running.")
        case "not_visible": L("Nobody can see your profile yet, so a boost wouldn't reach anyone.")
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
