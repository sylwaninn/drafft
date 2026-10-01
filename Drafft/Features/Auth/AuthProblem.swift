import Foundation
import Supabase

/// What went wrong with an account call, in words people can act on.
enum AuthProblem: Equatable {
    case wrongCredentials, emailNotConfirmed, emailTaken, invalidEmail, weakPassword, tooManyEmails, tooManyTries, samePassword, wrongCode,
         offline, other

    init(_ error: Error) {
        if error is Backend.EmailAlreadyRegistered {
            self = .emailTaken
        } else if let e = error as? AuthError {
            self = Self.hint(of: e) == "email_taken" ? .emailTaken : Self.from(e.errorCode)
        } else if error is URLError {
            self = .offline
        } else {
            self = .other
        }
    }

    /// A refusal from the database behind Auth (a trigger on auth.users), which Auth passes on as is:
    /// its `private.fail` code. An address a banned account used is `email_taken`, like any taken one.
    static func hint(of error: AuthError) -> String? {
        guard case let .api(_, _, data, _) = error else { return nil }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["hint"] as? String
    }

    private static func from(_ code: ErrorCode) -> AuthProblem {
        switch code {
        // An account closed for good (kept for members' safety) can't log in: said like a wrong password,
        // which tells nothing about the account.
        case .invalidCredentials, .userBanned: .wrongCredentials
        case .emailNotConfirmed: .emailNotConfirmed
        case .userAlreadyExists, .emailExists: .emailTaken
        case ErrorCode("email_address_invalid"): .invalidEmail
        case .weakPassword: .weakPassword
        case .overEmailSendRateLimit: .tooManyEmails
        case .overRequestRateLimit: .tooManyTries
        case .samePassword: .samePassword
        // Supabase answers the same for a mistyped code and an old one.
        case .otpExpired, .reauthenticationNotValid: .wrongCode
        default: .other
        }
    }

    var message: String {
        switch self {
        case .wrongCredentials: L("Email or password is incorrect. Try again or reset your password.")
        case .emailNotConfirmed: L("Confirm your email first: enter the code we sent you.")
        case .emailTaken: L("There's already an account with this email. Log in instead.")
        case .invalidEmail: L("That doesn't look like an email address. Check for typos.")
        case .weakPassword: L("Pick a stronger password.")
        case .tooManyEmails: L("Too many emails sent. Wait a few minutes and try again.")
        case .tooManyTries: L("Too many tries. Wait a few minutes and try again.")
        case .samePassword: L("Pick something different from your current password.")
        case .wrongCode: L("Wrong or expired code. Check it, or send a new one.")
        case .offline: L("Couldn't connect. Check your connection and try again.")
        case .other: L("Something went wrong. Try again in a moment.")
        }
    }
}
