import Foundation

/// What Sign in with Apple / Google actually give an app, nothing more.
///
/// - Apple: a stable user ID; an email (the real one, or a private relay address if the person
///   hides it), always verified; the name only on the very first sign-in, and only if shared
///   (it can be edited by the person). No photo, birthday, gender or phone number.
/// - Google (openid, email, profile scopes): a stable user ID ("sub"), the email and whether it's
///   verified, the full / given / family name, a profile picture URL and a locale. No birthday,
///   gender or phone without extra, reviewed scopes.
struct SocialIdentity: Equatable {
    enum Provider: String, Identifiable { case apple = "Apple", google = "Google"; var id: String { rawValue } }

    let provider: Provider
    let userID: String
    let email: String?
    let emailVerified: Bool
    /// Apple "Hide My Email" relay address.
    let isPrivateRelay: Bool
    let givenName: String?
    let familyName: String?
    /// Google only.
    let pictureURL: URL?
    /// First sign-in with this provider (Apple only sends the name then).
    let isNewUser: Bool

    /// Everything the provider shared, for the "we got this from…" note.
    var sharedFields: [String] {
        var f: [String] = []
        if givenName != nil { f.append("first name") }
        if email != nil { f.append(isPrivateRelay ? "a private relay email" : "email") }
        if pictureURL != nil { f.append("profile picture") }
        return f
    }
}

/// Demo stand-in for AuthenticationServices / GoogleSignIn: returns the same shape of data.
enum DemoSocialAuth {
    static func apple(shareEmail: Bool, name: (String, String)?, newUser: Bool) -> SocialIdentity {
        SocialIdentity(provider: .apple, userID: "001234.a1b2c3d4e5f6.0101",
                       email: shareEmail ? "alex.martin@icloud.com" : "k7x2qfp9m4@privaterelay.appleid.com",
                       emailVerified: true, isPrivateRelay: !shareEmail,
                       givenName: newUser ? name?.0 : nil, familyName: newUser ? name?.1 : nil,
                       pictureURL: nil, isNewUser: newUser)
    }

    static func google(newUser: Bool) -> SocialIdentity {
        SocialIdentity(provider: .google, userID: "109876543210987654321",
                       email: "alex.martin@gmail.com", emailVerified: true, isPrivateRelay: false,
                       givenName: "Alex", familyName: "Martin",
                       pictureURL: URL(string: "https://lh3.googleusercontent.com/a/demo-avatar"),
                       isNewUser: newUser)
    }
}
