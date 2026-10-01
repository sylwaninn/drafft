import Foundation
import Supabase

/// The drafft backend: Supabase Auth for the account (email + password; the session lives in the
/// Keychain and refreshes itself), plus the plain HTTPS calls the app makes as the signed-in person
/// (RPCs, Edge Functions, a few table reads and writes).
actor Backend {
    static let shared = Backend()

    enum BackendError: Error, LocalizedError {
        /// The status, and the server's code (`hint`, else its `code`) or, without one, its message.
        case http(Int, String)
        case signedOut
        /// Shown on screen: the known code's words, or a generic line (never the server's reply).
        var errorDescription: String? {
            switch self {
            case let .http(_, message): ServerMessage.text(forCode: message) ?? ServerMessage.generic
            case .signedOut: L("You've been logged out. Log in again to continue.")
            }
        }
    }

    /// Nonisolated so the auth calls below don't queue behind a slow request.
    nonisolated let client = SupabaseClient(
        supabaseURL: BackendConfig.url,
        supabaseKey: BackendConfig.publishableKey,
        options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
    )

    /// Whether someone is signed in on this device.
    var hasSession: Bool { client.auth.currentSession != nil }

    /// The signed-in person's id (the profile id everywhere on the server).
    var userID: UUID? { client.auth.currentUser?.id }

    /// A valid access token (refreshed by the SDK when it's about to expire). Signed out only when Auth
    /// turned the session down; a refresh that couldn't reach it (offline, a server error) throws that
    /// error, and the session stays.
    func accessToken() async throws -> String {
        do {
            return try await client.auth.session.accessToken
        } catch where Self.refusesSession(error) {
            throw BackendError.signedOut
        }
    }

    /// Whether Auth turned the session down for good (none saved, revoked, expired, the account gone),
    /// as opposed to not answering: only that ends a session.
    nonisolated static func refusesSession(_ error: Error) -> Bool {
        switch error as? AuthError {
        case .sessionMissing?: true
        case let .api(_, code, _, response)?:
            (400..<500).contains(response.statusCode) && code != .overRequestRateLimit
        default: false
        }
    }

    // MARK: Account

    enum SignUpResult { case signedIn, confirmEmail }
    struct EmailAlreadyRegistered: Error {}

    /// A new account. With email confirmation on, there's no session until the 6-digit code in the
    /// email is typed in (`confirmSignUp`). `language` starts the
    /// profile in it, so the confirmation email (backend auth-email) is already in that language.
    func signUp(email: String, password: String, language: AppLanguage) async throws -> SignUpResult {
        let response = try await client.auth.signUp(
            email: email, password: password, data: ["language": .string(language.rawValue)]
        )
        // An address that already has an account: Supabase doesn't say so (that would tell who's signed up),
        // it answers like a new sign-up with no identity and sends nothing. The app says it plainly.
        if response.session == nil, response.user.identities?.isEmpty == true { throw EmailAlreadyRegistered() }
        return response.session == nil ? .confirmEmail : .signedIn
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    /// The 6-digit code from the sign-up email: the account is confirmed and signed in.
    func confirmSignUp(_ email: String, code: String) async throws {
        try await client.auth.verifyOTP(email: email, token: code, type: .signup)
    }

    func resendConfirmation(to email: String) async throws {
        try await client.auth.resend(email: email, type: .signup)
    }

    /// Emails a 6-digit code to reset the password (backend auth-email, recovery). Auth answers the same
    /// whether or not the address has an account.
    func sendPasswordReset(to email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    /// The code from `sendPasswordReset`: signs in, so the new password can be set (`updatePassword(_:)`).
    func verifyPasswordReset(_ email: String, code: String) async throws {
        try await client.auth.verifyOTP(email: email, token: code, type: .recovery)
    }

    /// Emails a 6-digit code to the new address (the "Change email address" template shows `{{ .Token }}`).
    func updateEmail(_ email: String) async throws {
        try await client.auth.update(user: UserAttributes(email: email))
    }

    /// The code from `updateEmail`: the address switches once it checks out.
    func confirmEmailChange(_ email: String, code: String) async throws {
        try await client.auth.verifyOTP(email: email, token: code, type: .emailChange)
    }

    /// Emails a 6-digit code to the current address, to prove it's them before a password change.
    func sendReauthenticationCode() async throws {
        try await client.auth.reauthenticate()
    }

    /// After a password reset code (the code proved it's them).
    func updatePassword(_ password: String) async throws {
        try await client.auth.update(user: UserAttributes(password: password))
    }

    /// A new password, with the code from `sendReauthenticationCode`.
    func updatePassword(_ password: String, code: String) async throws {
        try await client.auth.update(user: UserAttributes(password: password, nonce: code))
    }

    /// Texts a 6-digit code to the number: the phone-code function checks the account (email confirmed),
    /// the limits and the line, then starts the Supabase Auth phone change. Refusals keep the server's code.
    func updatePhone(_ e164: String) async throws {
        _ = try await function("phone-code", ["phone": e164])
    }

    func confirmPhoneChange(_ e164: String, code: String) async throws {
        try await client.auth.verifyOTP(phone: e164, token: code, type: .phoneChange)
    }

    /// This device's Auth session (the `session_id` claim of its access token): a `session_revoked`
    /// event names the sessions that ended.
    var sessionID: String? {
        guard let token = client.auth.currentSession?.accessToken else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (claims["session_id"] as? String)?.lowercased()
    }

    /// Signs out on this device only (other devices stay signed in).
    func signOut() async {
        try? await client.auth.signOut(scope: .local)
    }

    // MARK: Calls

    /// POST /rest/v1/rpc/<name>, as the signed-in person.
    func rpc(_ name: String, _ body: [String: Any]) async throws -> Data {
        try await request("POST", "rest/v1/rpc/\(name)", json: body)
    }

    /// POST /functions/v1/<name>, as the signed-in person.
    func function(_ name: String, _ body: [String: Any]) async throws -> Data {
        try await request("POST", "functions/v1/\(name)", json: body)
    }

    /// POST /functions/v1/<name>, signed in or not: with the person's token when there is one (the
    /// function reads it), with only the app's key otherwise (support, from a stuck sign-up).
    func publicFunction(_ name: String, _ body: [String: Any]) async throws -> Data {
        try await request("POST", "functions/v1/\(name)", json: body, requiresSession: false)
    }

    /// GET on a table with PostgREST filters, e.g. `profile_media?id=eq.…&select=status`.
    func select(_ pathAndQuery: String) async throws -> Data {
        try await request("GET", "rest/v1/\(pathAndQuery)", json: nil)
    }

    /// PATCH the person's own profile row (only the columns the server lets the app write).
    func updateMyProfile(_ fields: [String: Any]) async throws {
        guard let id = userID else { throw BackendError.signedOut }
        _ = try await request("PATCH", "rest/v1/profiles?id=eq.\(id)", json: fields)
    }

    /// The person's own profile row, with these columns (comma-separated). A JSON array of one.
    func myProfile(select columns: String) async throws -> Data {
        guard let id = userID else { throw BackendError.signedOut }
        return try await request("GET", "rest/v1/profiles?id=eq.\(id)&select=\(columns)", json: nil)
    }

    // MARK: HTTP

    /// The server refused because the profile is paused: a database function's hint `paused`, an
    /// edge function's 403 with code `paused`, or the chat service's "user is banned" (the pause ban).
    static func saysPaused(status: Int, body: [String: Any]?) -> Bool {
        let hint = body?["hint"] as? String, code = body?["code"] as? String
        let text = ((body?["message"] ?? body?["msg"] ?? body?["error"]) as? String ?? "").lowercased()
        return hint == "paused" || (status == 403 && code == "paused") || text.contains("user is banned")
    }

    private func request(_ method: String, _ path: String, json: [String: Any]?,
                         requiresSession: Bool = true) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: BackendConfig.url)!)
        request.httpMethod = method
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if requiresSession || hasSession {
            request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        }
        if let json { request.httpBody = try JSONSerialization.data(withJSONObject: json) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            // PostgREST sends `"hint": null` when there's no code (NSNull here): skip it, not stop at it.
            let message = ["hint", "msg", "message", "code"].lazy.compactMap { body?[$0] as? String }.first
            // On hold (moderation): a database function's hint or an edge function's 403 `moderated`.
            if body?["hint"] as? String == "moderated" || (status == 403 && body?["code"] as? String == "moderated") {
                await MainActor.run { NotificationCenter.default.post(name: .accountHeldByServer, object: nil) }
            } else if Self.saysPaused(status: status, body: body) {
                await MainActor.run { NotificationCenter.default.post(name: .profilePausedByServer, object: nil) }
            }
            throw BackendError.http(status, message ?? String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data
    }
}

extension Notification.Name {
    /// Posted when the server turns an action down because the profile is paused.
    static let profilePausedByServer = Notification.Name("profilePausedByServer")
    /// Posted when the server turns an action down because the account is on hold (moderation).
    static let accountHeldByServer = Notification.Name("accountHeldByServer")
}
