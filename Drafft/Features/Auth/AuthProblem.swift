import Foundation
import Supabase

/// What went wrong with an account call, in words people can act on.
enum AuthProblem: Equatable {
    case wrongCredentials, emailNotConfirmed, emailTaken, weakPassword, tooManyEmails, samePassword, wrongCode, offline, other

    init(_ error: Error) {
        if error is Backend.EmailAlreadyRegistered {
            self = .emailTaken
        } else if let e = error as? AuthError {
            self = Self.from(e.errorCode)
        } else if error is URLError {
            self = .offline
        } else {
            self = .other
        }
    }

    private static func from(_ code: ErrorCode) -> AuthProblem {
        switch code {
        case .invalidCredentials: .wrongCredentials
        case .emailNotConfirmed: .emailNotConfirmed
        case .userAlreadyExists, .emailExists: .emailTaken
        case .weakPassword: .weakPassword
        case .overEmailSendRateLimit: .tooManyEmails
        case .samePassword: .samePassword
        // Supabase answers the same for a mistyped code and an old one.
        case .otpExpired, .reauthenticationNotValid: .wrongCode
        default: .other
        }
    }

    var message: String {
        switch self {
        case .wrongCredentials: L("Email or password is incorrect. Try again or reset your password.")
        case .emailNotConfirmed: L("Confirm your email first: open the link we sent you.")
        case .emailTaken: L("There's already an account with this email. Log in instead.")
        case .weakPassword: L("Pick a stronger password.")
        case .tooManyEmails: L("Too many emails sent. Wait a few minutes and try again.")
        case .samePassword: L("Pick something different from your current password.")
        case .wrongCode: L("Wrong or expired code. Check it, or send a new one.")
        case .offline: L("Couldn't connect. Check your connection and try again.")
        case .other: L("Something went wrong. Try again in a moment.")
        }
    }
}
