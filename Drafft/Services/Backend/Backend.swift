import Foundation
import Supabase

/// The drafft backend: Supabase Auth for the account (email + password; the session lives in the
/// Keychain and refreshes itself), plus the plain HTTPS calls the app makes as the signed-in person
/// (RPCs, Edge Functions, a few table reads and writes).
actor Backend {
    static let shared = Backend()

    enum BackendError: Error, LocalizedError {
        case http(Int, String)
        case signedOut
        var errorDescription: String? {
            switch self {
            case let .http(status, message): "Backend \(status): \(message)"
            case .signedOut: "Not signed in"
            }
        }
    }

    /// Where the links in auth emails bring people back: the app. One address per email, since the
    /// link itself doesn't say which it was. Both must be in the project's Auth redirect URLs.
    static let authCallback = URL(string: "drafft://auth-callback")!
    static let resetCallback = URL(string: "drafft://auth-callback/reset")!

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

    /// A valid access token (refreshed by the SDK when it's about to expire).
    func accessToken() async throws -> String {
        do { return try await client.auth.session.accessToken } catch { throw BackendError.signedOut }
    }

    // MARK: Account

    enum SignUpResult { case signedIn, confirmEmail }

    /// A new account. With email confirmation on (production), there's no session until the link in
    /// the email is opened: the app then asks the person to confirm and log in.
    func signUp(email: String, password: String) async throws -> SignUpResult {
        let response = try await client.auth.signUp(email: email, password: password, redirectTo: Self.authCallback)
        return response.session == nil ? .confirmEmail : .signedIn
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func resendConfirmation(to email: String) async throws {
        try await client.auth.resend(email: email, type: .signup, emailRedirectTo: Self.authCallback)
    }

    func sendPasswordReset(to email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: Self.resetCallback)
    }

    enum AuthLink { case confirmed, resetPassword }

    /// A link from an auth email opened the app: its code becomes the session.
    func handleAuthLink(_ url: URL) async throws -> AuthLink {
        try await client.auth.session(from: url)
        return url.path == Self.resetCallback.path ? .resetPassword : .confirmed
    }

    /// Whether the signed-in person finished sign-up (`profiles.onboarded_at`).
    func isOnboarded() async throws -> Bool {
        let data = try await myProfile(select: "onboarded_at")
        let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        return rows?.first?["onboarded_at"] is String
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

    /// After a reset link (the link itself proved it's them).
    func updatePassword(_ password: String) async throws {
        try await client.auth.update(user: UserAttributes(password: password))
    }

    /// A new password, with the code from `sendReauthenticationCode`.
    func updatePassword(_ password: String, code: String) async throws {
        try await client.auth.update(user: UserAttributes(password: password, nonce: code))
    }

    /// Texts a 6-digit code to the number (Supabase Auth phone change; needs an SMS provider).
    func updatePhone(_ e164: String) async throws {
        try await client.auth.update(user: UserAttributes(phone: e164))
    }

    func confirmPhoneChange(_ e164: String, code: String) async throws {
        try await client.auth.verifyOTP(phone: e164, token: code, type: .phoneChange)
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

    private func request(_ method: String, _ path: String, json: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: BackendConfig.url)!)
        request.httpMethod = method
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        if let json { request.httpBody = try JSONSerialization.data(withJSONObject: json) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["hint"] ?? $0["msg"] ?? $0["message"] ?? $0["code"] } as? String
            throw BackendError.http(status, message ?? String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data
    }
}
