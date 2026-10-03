import UIKit
import UserNotifications
import Observation

/// Notifications: permission, the per-type preferences, and the push plumbing (device token). Session
/// reminders are the server's pushes (`session.reminder`, following `notify_session_*`): checked against
/// the session when they're sent, so a cancelled or changed one never reminds anyone. Tapping a
/// notification opens its page (`PushRoute`): the tap is kept until the tabs are on screen, then
/// `AppModel.follow` takes it there.
@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, SystemPermission {
    static let shared = NotificationService()

    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// APNs device token (hex), to send to the server once it exists.
    private(set) var deviceToken: String?
    /// The tap queue (`PushTapQueue`): the last tapped notification, until the tabs are on screen to follow
    /// it (MainTabs takes it). A cold launch sets it before any screen exists; a newer tap replaces it.
    private var taps = PushTapQueue(skipped: AppModel.trackSkippedPush)
    var pendingRoute: PendingPushRoute? { taps.pending }

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
        let before = await center.notificationSettings().authorizationStatus
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refresh()
        // Already allowed (the usual case): nothing was asked, so nothing to count.
        let result: AnalyticsEvent.PermissionResult? = switch before {
        case .notDetermined: granted ? .granted : .denied
        // iOS doesn't prompt again: only Settings can turn it on.
        case .denied: .blocked
        default: nil
        }
        if let result { Telemetry.track(.permissionRequested(.notifications, result: result, during: ScreenTracker.currentID)) }
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

    // MARK: Taps

    /// The tapped notification to follow now, once: the tabs are on screen (MainTabs).
    /// One that waited over its lifetime is counted and dropped.
    func takePendingRoute() -> PendingPushRoute? { taps.take() }

    /// Signed out: a tap meant for the account that left goes nowhere.
    func dropPendingRoute() { taps.drop() }

    private func queue(_ route: PushRoute) {
        taps.tap(route, account: Backend.shared.client.auth.currentUser?.id.uuidString)
    }

    private let registration = PushTokenRegistration()

    // MARK: Settings

    private static let settingsKey = "notificationSettings"
    /// Set while settings from the phone or the server are applied: nothing is saved or sent back.
    private var applying = false
    private static let unsentKey = "notificationSettingsUnsent"
    /// The account whose settings changed here and haven't reached the server yet (offline, a failed
    /// save): kept over the server's copy, and sent again at each account read until one goes through.
    @ObservationIgnored private var unsentFor: String? {
        get { UserDefaults.standard.string(forKey: Self.unsentKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.unsentKey) }
    }
    /// Bumped by each send: only the latest one clears `unsentFor`.
    @ObservationIgnored private var sends = 0

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
        trackChanges(to: current)
        if let data = try? JSONEncoder().encode(current) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
        guard let account = Backend.shared.client.auth.currentUser?.id.uuidString else { return }
        unsentFor = account
        send(current, for: account)
    }

    /// Each switch the person flipped (`notify_matches` off...); the language has its own event.
    private func trackChanges(to now: NotificationSettings) {
        guard let data = UserDefaults.standard.data(forKey: Self.settingsKey),
              let before = try? JSONDecoder().decode(NotificationSettings.self, from: data) else { return }
        let was = before.fields
        for (key, value) in now.fields where key != "language" {
            guard let enabled = value as? Bool, was[key] as? Bool != enabled else { continue }
            Telemetry.track(.notificationSettingChanged(key, enabled: enabled))
        }
    }

    /// The switch stays as the person set it: a save that fails is sent again at the next account
    /// read (return to the app), never undone by the server's older copy.
    private func send(_ settings: NotificationSettings, for account: String) {
        sends += 1
        let send = sends
        Task {
            do {
                try await Backend.shared.updateMyProfile(settings.fields)
                if send == sends, unsentFor == account { unsentFor = nil }
            } catch {
                // Still marked unsent: `applyServer` sends it again.
            }
        }
    }

    /// The settings saved on the profile (another device, a reinstall) replace the phone's, unless
    /// this phone has a change the server hasn't got yet: that one is sent again instead. Read with
    /// the rest of the profile row (`AppModel.refreshAccount`).
    func applyServer(_ remote: NotificationSettings) {
        if let account = Backend.shared.client.auth.currentUser?.id.uuidString, unsentFor == account {
            send(current, for: account)
            return
        }
        // Another account's leftover: this one's server copy wins.
        unsentFor = nil
        applying = true
        apply(remote)
        applying = false
        if let data = try? JSONEncoder().encode(remote) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
    }

    // MARK: From a person

    /// A notification about someone, shown right away: their name as the title (the event for an
    /// anonymous like), one sentence as the body ("Nouveau message.", or the text with previews on), their
    /// photo as the thumbnail. Away from the app these come as pushes (Stream for messages, db-events for
    /// the rest); while the chat is connected (the app open, or just left), Stream doesn't push, so a
    /// message from another chat is posted here, under the same settings. `preview` is the message text,
    /// used when message previews are on.
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
        content.title = NotificationText.title(kind, name: name, in: language)
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
        let info = notification.request.content.userInfo
        let route = PushRoute(userInfo: info)
        Telemetry.track(.pushReceived(route.kind.rawValue, inForeground: true))
        switch route.kind {
        case .photoRefused:
            // A refused photo while the app is open: its own banner says it, not the system's (shown
            // once, whether the push or the live `media` event comes first).
            if case .photoRefusal(let media) = route.destination {
                await MainActor.run { PhotoModeration.shared.apply(mediaID: media, status: "rejected") }
            }
            return []
        case .moderation:
            // Moderation news (a hold lifted, a selfie asked for): the open app's screen already changed
            // live (Realtime `moderation`), so the system banner would say it twice.
            return []
        case .sessionCancelled, .sessionReminder:
            // A session changed while the app is open: the push says it, the cards follow (the Realtime
            // event usually got there first; this read catches a missed one).
            await SessionStore.shared.refresh()
        default:
            break
        }
        return [.banner, .sound]
    }

    /// A tap on a notification (the app open, in the background, or launched by the tap). Read here,
    /// followed by MainTabs once the tabs are on screen (`AppModel.follow`): on a cold launch the
    /// session, the matches and the screens aren't there yet.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        let route = PushRoute(userInfo: response.notification.request.content.userInfo)
        // `push_opened` is sent once it's followed (`AppModel.follow`), with whether it got there.
        await MainActor.run {
            // A cancelled session: read again (its card, its calendar event), without holding the route.
            if route.kind == .sessionCancelled { Task { await SessionStore.shared.refresh() } }
            self.queue(route)
        }
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

/// Receives the APNs device token, sets the notification delegate at launch, and gets the background upload
/// events iOS relaunches the app for.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The delegate must be set before launch ends, or the tap that launched the app is never
        // delivered (`userNotificationCenter(_:didReceive:)`): `shared` sets it.
        MainActor.assumeIsolated { _ = NotificationService.shared }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { NotificationService.shared.didRegister(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected until the push capability and the server are set up.
    }

    /// iOS relaunched the app because the uploads session has events (an upload finished while the app was
    /// closed): hand the completion to the uploader, which calls it once the session has delivered them all.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == MediaUploader.sessionIdentifier else { return completionHandler() }
        // Safe: iOS gives this handler to the main thread and the uploader only ever calls it there (the wrapper
        // is what lets the compiler accept the conversion to a Sendable closure).
        nonisolated(unsafe) let completion = completionHandler
        MediaUploader.shared.handleEventsForBackgroundSession { completion() }
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
