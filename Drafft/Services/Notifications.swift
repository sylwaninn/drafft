import UIKit
import UserNotifications
import Observation

/// Notifications: permission, the per-type preferences, and the push plumbing (device token). Session
/// reminders are the server's pushes (`session.reminder`, following `notify_session_*`): checked against
/// the session when they're sent, so a cancelled or changed one never reminds anyone. Tapping a
/// notification opens its chat.
@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, SystemPermission {
    static let shared = NotificationService()

    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// APNs device token (hex), to send to the server once it exists.
    private(set) var deviceToken: String?
    /// A chat to open, set when a notification is tapped.
    var openChatID: String?
    /// Set when the weekly-boost notification is tapped: Discover opens, where the boost is used.
    var openBoost = false
    /// Set when a session's cancellation without a chat is tapped: the Sessions tab opens.
    var openSessions = false

    /// Language of the notification texts: the app's language (set by AppModel).
    var language: AppLanguage = Localization.shared.language {
        didSet { changed() }
    }

    // Preferences. Saved on the profile (the server's pushes follow them, and they come back on a new
    // device) and on the phone (right at launch, offline too). See `applyServer`.
    var matches = true { didSet { changed() } }
    var messages = true { didSet { changed() } }
    var messagePreviews = false { didSet { changed() } }
    var reactions = true { didSet { changed() } }
    var likes = true { didSet { changed() } }
    /// Session reminders, sent by the server: the evening before (20:00 in the person's time zone) and
    /// an hour before.
    var sessionEvening = true { didSet { changed() } }
    var sessionHourBefore = true { didSet { changed() } }
    /// drafft tempo's weekly boost: pushed by the server when it credits it (`notify_weekly_boost`).
    var weeklyBoost = true { didSet { changed() } }

    var isAllowed: Bool { status == .authorized || status == .provisional || status == .ephemeral }
    var isDenied: Bool { status == .denied }

    // SystemPermission
    var permission: PermissionStatus { isAllowed ? .allowed : isDenied ? .denied : .notAsked }
    var settingsURL: URL? { URL(string: UIApplication.openNotificationSettingsURLString) }

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        // The weekly boost is the server's now (credit and push): drop the local one older builds scheduled.
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-boost"])
        // Session reminders are the server's now: drop the local ones older builds scheduled
        // ("<session>-eve", "<session>-1h"), which wouldn't follow a cancellation.
        center.getPendingNotificationRequests { requests in
            let old = requests.map(\.identifier).filter { $0.hasSuffix("-eve") || $0.hasSuffix("-1h") }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: old)
        }
        // Always current: every return to the app (from Settings too) re-reads the permission, so no
        // screen has to refresh it.
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            applying = true
            apply(saved)
            applying = false
        }
    }

    func refresh() async {
        status = await center.notificationSettings().authorizationStatus
        if isAllowed { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// The system prompt. Returns whether notifications are on.
    @discardableResult
    func requestPermission() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refresh()
        return granted
    }

    func didRegister(token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        Task { await syncPushToken() }
        // Messages are pushed by Stream: the chat registers the same token there.
        ChatService.shared.registerDevice(token)
        // Until the server registers tokens (register_push_token), keep the last one in the app's
        // Documents, readable over the cable with `xcrun devicectl device copy from`, to test pushes.
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? hex.write(to: docs.appendingPathComponent("apns-token.txt"), atomically: true, encoding: .utf8)
        }
    }

    /// Registers this device with the backend so it can push (photo refused, match, session…).
    /// Only once a backend session exists: it never creates an account by itself.
    /// Sent only when the token, the account or the environment changed (or a day went by): every
    /// return to the app hands the same token back.
    func syncPushToken() async {
        guard let token = deviceToken, let account = await Backend.shared.userID else { return }
        let environment = PushEnvironment.current
        guard registration.needsSending(token: token, account: account, environment: environment) else { return }
        do {
            _ = try await Backend.shared.rpc("register_push_token", ["p_token": token, "p_environment": environment])
            registration.markSent(token: token, account: account, environment: environment)
        } catch {
            // Not remembered: the next return to the app sends it again.
        }
    }

    /// Signed out: this device stops getting the account's pushes. The next account (or the same
    /// one, signed in again) registers the token afresh.
    func unregisterPushToken() async {
        forgetPushTokenRegistration()
        guard let token = deviceToken else { return }
        _ = try? await Backend.shared.rpc("unregister_push_token", ["p_token": token])
    }

    func forgetPushTokenRegistration() { registration.forget() }

    private let registration = PushTokenRegistration()

    // MARK: Settings

    private static let settingsKey = "notificationSettings"
    /// Set while settings from the phone or the server are applied: nothing is saved or sent back.
    private var applying = false

    private var current: NotificationSettings {
        NotificationSettings(language: language, matches: matches, likes: likes, messages: messages,
                             messagePreviews: messagePreviews, reactions: reactions, sessionEvening: sessionEvening,
                             sessionHourBefore: sessionHourBefore, weeklyBoost: weeklyBoost)
    }

    private func apply(_ s: NotificationSettings) {
        if Localization.shared.language != s.language { Localization.shared.language = s.language }
        language = s.language
        matches = s.matches
        likes = s.likes
        messages = s.messages
        messagePreviews = s.messagePreviews
        reactions = s.reactions
        sessionEvening = s.sessionEvening
        sessionHourBefore = s.sessionHourBefore
        weeklyBoost = s.weeklyBoost
    }

    /// A setting (or the language) changed: saved on the phone, sent to the profile. Only real
    /// changes are sent, never the defaults at launch.
    private func changed() {
        guard !applying else { return }
        if let data = try? JSONEncoder().encode(current) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
        let settings = current
        Task {
            guard await Backend.shared.hasSession else { return }
            try? await Backend.shared.updateMyProfile(settings.fields)
        }
    }

    /// The settings saved on the profile (another device, a reinstall) replace the phone's. Read
    /// with the rest of the profile row (`AppModel.refreshAccount`).
    func applyServer(_ remote: NotificationSettings) {
        applying = true
        apply(remote)
        applying = false
        if let data = try? JSONEncoder().encode(remote) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
    }

    // MARK: From a person

    /// A notification about someone, shown right away: "drafft" as the title, the whole sentence
    /// ("Maya t'a envoyé un message") as the body, their photo as the thumbnail. Away from the app these
    /// come as pushes (Stream for messages, db-events for the rest); while the chat is connected (the app
    /// open, or just left), Stream doesn't push, so a message from another chat is posted here, under the
    /// same settings. `preview` is the message text, used when message previews are on.
    func notify(_ kind: NotificationText.Kind, from name: String, photo: String?, chatID: String,
                muted: Bool, preview: String? = nil) async {
        guard isAllowed, !muted else { return }
        switch kind {
        case .message, .sessionProposed, .sessionAccepted, .sessionDeclined, .sessionCancelled:
            guard messages else { return }
        case .like, .superLike:
            guard likes else { return }
        case .match:
            guard matches else { return }
        case .reaction:
            guard messages, reactions else { return }
        }
        let content = UNMutableNotificationContent()
        content.title = NotificationText.title
        content.body = if case .message = kind, messagePreviews, let preview {
            NotificationText.preview(preview, name: name, in: language)
        } else if case .reaction(let emoji, _) = kind, !messagePreviews {
            // Previews off: which message it was stays in the app.
            NotificationText.body(.reaction(emoji, nil), name: name, in: language)
        } else {
            NotificationText.body(kind, name: name, in: language)
        }
        content.sound = .default
        content.threadIdentifier = chatID
        content.userInfo = ["chatID": chatID]
        if let photo, let attachment = Self.thumbnail(photo) { content.attachments = [attachment] }
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Square, small JPEG of a profile photo, as a notification attachment (the system moves the
    /// file into its own store).
    private static func thumbnail(_ asset: String) -> UNNotificationAttachment? {
        guard let image = UIImage(named: asset) else { return nil }
        let side: CGFloat = 300
        let scale = side / min(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notif-\(UUID().uuidString).jpg")
        guard let data = square.jpegData(compressionQuality: 0.8), (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "photo", url: url)
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        // A refused photo while the app is open: its own banner says it, not the system's (shown once,
        // whether the push or the live `media` event comes first).
        let info = notification.request.content.userInfo
        if info["kind"] as? String == "photo_refused" {
            if let media = info["media"] as? String {
                await MainActor.run { PhotoModeration.shared.apply(mediaID: media, status: "rejected") }
            }
            return []
        }
        // A session changed while the app is open: the push says it, the cards follow (the Realtime event
        // usually got there first; this read catches a missed one).
        if let kind = info["kind"] as? String, kind == "session_cancelled" || kind == "session_reminder" {
            await SessionStore.shared.refresh()
        }
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if info["kind"] as? String == "photo_refused", let media = info["media"] as? String {
            await MainActor.run { PhotoModeration.shared.openRefusal(mediaID: media) }
            return
        }
        if info["kind"] as? String == "weekly_boost" {
            await MainActor.run { self.openBoost = true }
            return
        }
        // Server pushes name the match (its chat); the app's own name the chat.
        let chatID = (info["chatID"] as? String) ?? (info["match"] as? String)?.lowercased()
        if let kind = info["kind"] as? String, kind == "session_cancelled" {
            // Cancelled with its match (no chat any more): the Sessions tab, read again.
            await SessionStore.shared.refresh()
            if chatID == nil {
                await MainActor.run { self.openSessions = true }
                return
            }
        }
        await MainActor.run { self.openChatID = chatID }
    }
}

/// The notification settings and the app's language, as saved on the profile (`profiles` columns).
struct NotificationSettings: Codable {
    var language: AppLanguage
    var matches, likes, messages, messagePreviews, reactions, sessionEvening, sessionHourBefore, weeklyBoost: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case language
        case matches = "notify_matches"
        case likes = "notify_likes"
        case messages = "notify_messages"
        case messagePreviews = "notify_message_previews"
        case reactions = "notify_reactions"
        case sessionEvening = "notify_session_evening"
        case sessionHourBefore = "notify_session_hour_before"
        case weeklyBoost = "notify_weekly_boost"
    }

    static var columns: String { CodingKeys.allCases.map(\.rawValue).joined(separator: ",") }

    /// The PATCH body.
    var fields: [String: Any] {
        ["language": language.rawValue, "notify_matches": matches, "notify_likes": likes,
         "notify_messages": messages, "notify_message_previews": messagePreviews, "notify_reactions": reactions,
         "notify_session_evening": sessionEvening, "notify_session_hour_before": sessionHourBefore,
         "notify_weekly_boost": weeklyBoost]
    }
}

/// Receives the APNs device token.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { NotificationService.shared.didRegister(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected until the push capability and the server are set up.
    }
}

/// Which APNs environment this build's pushes go through: `sandbox` for builds installed from Xcode
/// (development signing), `production` for TestFlight and the App Store.
enum PushEnvironment {
    static let current: String = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return "production" } // App Store
        let text = String(decoding: data, as: UTF8.self)
        guard let range = text.range(of: "<key>aps-environment</key>") else { return "production" }
        return text[range.upperBound...].prefix(80).contains("development") ? "sandbox" : "production"
    }()
}
