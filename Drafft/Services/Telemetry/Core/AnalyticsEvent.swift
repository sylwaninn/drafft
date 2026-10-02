import Foundation

// The catalog mirrors the Android app's event by event: some events carry many properties.
// swiftlint:disable discouraged_optional_boolean function_parameter_count

/// Every product event the app sends, in one place: the tracking plan (docs/telemetry.md) as code.
///
/// Naming: `object_action`, snake_case, past tense (`profile_swiped`, `purchase_completed`), the way
/// PostHog recommends. Properties are numbers, booleans and codes from enums, never what people type or
/// the sensitive data of their profile (`PrivacyGuard` drops it anyway). An event's name and its
/// properties' names are a contract with the dashboards: add new ones, don't rename.
///
/// The Android app sends the same events with the same names (`AnalyticsEvent.kt`), so a funnel spans
/// both platforms.
struct AnalyticsEvent: Sendable {
    let name: String
    let properties: TelemetryProperties

    init(_ name: String, _ properties: TelemetryProperties = [:]) {
        self.name = name
        self.properties = properties
    }

    // MARK: Values

    enum AuthMethod: String, CaseIterable, TelemetryValueConvertible { case email }
    enum SwipeAction: String, CaseIterable, TelemetryValueConvertible { case like, pass, superLike = "super_like" }
    enum SwipeSource: String, CaseIterable, TelemetryValueConvertible { case deck, likes, profile }
    enum MatchSource: String, CaseIterable, TelemetryValueConvertible { case mySwipe = "my_swipe", theirLike = "their_like" }
    enum MessageKind: String, CaseIterable, TelemetryValueConvertible {
        case text, photo, video, voice, file, session
        case icebreakerReply = "icebreaker_reply", photoReply = "photo_reply"
    }
    enum ProductKind: String, CaseIterable, TelemetryValueConvertible {
        case tempo, boost, superLike = "super_like"

        /// From the store's product id: `so.drafft.app.tempo.monthly`, `so.drafft.app.boost.5`.
        init(productID: String) {
            self = if productID.contains("boost") { .boost } else if productID.contains("super") { .superLike } else { .tempo }
        }
    }
    enum SessionResponse: String, CaseIterable, TelemetryValueConvertible { case accepted, declined }
    enum Permission: String, CaseIterable, TelemetryValueConvertible {
        case location, notifications, camera, microphone, photos, calendar
    }
    enum PermissionResult: String, CaseIterable, TelemetryValueConvertible {
        case granted, denied, alreadyGranted = "already_granted", blocked
    }

    // MARK: Account

    /// The account exists (its email still to confirm, or already signed in): sign-up's first step.
    static func accountCreated(_ method: AuthMethod) -> Self { .init("account_created", ["method": method]) }
    static func signUpFailed(_ reason: String) -> Self { .init("sign_up_failed", ["reason": reason]) }
    static let emailConfirmed = Self("email_confirmed")
    static let emailCodeResent = Self("email_code_resent")
    static func loggedIn(_ method: AuthMethod) -> Self { .init("logged_in", ["method": method]) }
    static func logInFailed(_ reason: String) -> Self { .init("log_in_failed", ["reason": reason]) }
    static let passwordResetRequested = Self("password_reset_requested")
    static let passwordResetCompleted = Self("password_reset_completed")
    static let loggedOut = Self("logged_out")
    /// The session ended without the person logging out (revoked, expired, deleted elsewhere).
    static func sessionEnded(_ reason: String) -> Self { .init("session_ended", ["reason": reason]) }
    static let accountDeleted = Self("account_deleted")
    static func accountDeleteFailed(_ reason: String) -> Self { .init("account_delete_failed", ["reason": reason]) }
    static let emailChanged = Self("email_changed")
    static let passwordChanged = Self("password_changed")
    static let dataExportRequested = Self("data_export_requested")
    static func termsAccepted(version: String, during: String) -> Self {
        .init("terms_accepted", ["terms_version": version, "during": during])
    }
    static func analyticsConsentChanged(_ value: AnalyticsConsent) -> Self { .init("analytics_consent_changed", ["consent": value]) }
    static let accountHeld = Self("account_held")

    // MARK: Sign-up (onboarding)

    static func onboardingStepViewed(step: String, chapter: String, index: Int, resumed: Bool) -> Self {
        .init("onboarding_step_viewed", ["step": step, "chapter": chapter, "step_index": index, "resumed": resumed])
    }
    static func onboardingStepCompleted(step: String, chapter: String, index: Int, skipped: Bool, seconds: Int) -> Self {
        .init("onboarding_step_completed",
              ["step": step, "chapter": chapter, "step_index": index, "skipped": skipped, "seconds_on_step": seconds])
    }
    static func onboardingStepBlocked(step: String, reason: String) -> Self {
        .init("onboarding_step_blocked", ["step": step, "reason": reason])
    }
    static func onboardingResumed(step: String, index: Int) -> Self { .init("onboarding_resumed", ["step": step, "step_index": index]) }
    /// Counts and yes/no only: never the answers.
    static func onboardingCompleted(photos: Int, sports: Int, prompts: Int, hasVoice: Bool, hasBio: Bool, hasIcebreaker: Bool,
                                    answeredLifestyle: Bool, notificationsAllowed: Bool, minutes: Int) -> Self {
        .init("onboarding_completed", [
            "photos_count": photos, "sports_count": sports, "prompts_count": prompts, "has_voice_intro": hasVoice,
            "has_bio": hasBio, "has_icebreaker": hasIcebreaker, "answered_lifestyle": answeredLifestyle,
            "notifications_allowed": notificationsAllowed, "minutes_this_session": minutes
        ])
    }
    static func onboardingFailed(_ reason: String) -> Self { .init("onboarding_failed", ["reason": reason]) }

    // MARK: Phone

    static func phoneCodeSent(during: String, resend: Bool) -> Self { .init("phone_code_sent", ["during": during, "resend": resend]) }
    static func phoneCodeFailed(during: String, reason: String) -> Self { .init("phone_code_failed", ["during": during, "reason": reason]) }
    static func phoneVerified(during: String) -> Self { .init("phone_verified", ["during": during]) }
    static func phoneVerificationFailed(during: String, reason: String) -> Self {
        .init("phone_verification_failed", ["during": during, "reason": reason])
    }

    // MARK: Discover

    static func deckLoaded(cards: Int, mode: String, exhausted: Bool, seconds: Double) -> Self {
        .init("deck_loaded", ["cards_count": cards, "mode": mode, "exhausted": exhausted, "load_seconds": seconds])
    }
    static func deckLoadFailed(_ reason: String) -> Self { .init("deck_load_failed", ["reason": reason]) }
    static func deckEmptyShown(exhausted: Bool) -> Self { .init("deck_empty_shown", ["exhausted": exhausted]) }
    static func profileSwiped(_ action: SwipeAction, source: SwipeSource, withOpener: Bool, premium: Bool,
                              likesLeft: Int?, deckSize: Int) -> Self {
        .init("profile_swiped", [
            "action": action, "source": source, "with_opener": withOpener, "is_premium": premium,
            "likes_left": likesLeft, "deck_size": deckSize
        ])
    }
    static func swipeRefused(_ action: SwipeAction, reason: String) -> Self { .init("swipe_refused", ["action": action, "reason": reason]) }
    static func swipeUndone(_ action: SwipeAction) -> Self { .init("swipe_undone", ["action": action]) }
    static let dailyLikeLimitReached = Self("daily_like_limit_reached")
    static func profileViewed(source: String, hasVoice: Bool, photos: Int) -> Self {
        .init("profile_viewed", ["source": source, "has_voice_intro": hasVoice, "photos_count": photos])
    }
    /// Distance and sports only: who someone wants to meet is sensitive, and never sent.
    static func filtersChanged(maxDistanceKm: Int, sports: Int, sharedSportsOnly: Bool) -> Self {
        .init("filters_changed", ["max_distance_km": maxDistanceKm, "sports_count": sports, "shared_sports_only": sharedSportsOnly])
    }
    static func boostStarted(left: Int) -> Self { .init("boost_started", ["boosts_left": left]) }
    static func boostFailed(_ reason: String) -> Self { .init("boost_failed", ["reason": reason]) }
    static func voiceIntroPlayed(where place: String) -> Self { .init("voice_intro_played", ["where": place]) }
    static let icebreakerAnswered = Self("icebreaker_answered")

    // MARK: Likes and matches

    static func likesViewed(count: Int, premium: Bool) -> Self { .init("likes_viewed", ["likes_count": count, "is_premium": premium]) }
    static func matchCreated(_ source: MatchSource) -> Self { .init("match_created", ["source": source]) }
    static func matchScreenAction(_ action: String) -> Self { .init("match_screen_action", ["action": action]) }
    static let unmatched = Self("unmatched")
    static let matchEnded = Self("match_ended")

    // MARK: Chat

    static func chatOpened(unread: Int, messages: Int) -> Self {
        .init("chat_opened", ["unread_count": unread, "messages_count": messages])
    }
    /// `isFirst`: nil when the phone can't tell (only the latest messages are loaded).
    static func messageSent(_ kind: MessageKind, isReply: Bool, isFirst: Bool?, durationSeconds: Int?) -> Self {
        .init("message_sent", ["kind": kind, "is_reply": isReply, "is_first_message": isFirst, "duration_seconds": durationSeconds])
    }
    static func messageFailed(_ kind: MessageKind, reason: String) -> Self { .init("message_failed", ["kind": kind, "reason": reason]) }
    static let messageRetried = Self("message_retried")
    static func messageReacted(removed: Bool) -> Self { .init("message_reacted", ["removed": removed]) }
    static let messageDeleted = Self("message_deleted")
    static func chatMuted(_ muted: Bool) -> Self { .init("chat_muted", ["muted": muted]) }
    static let chatMarkedUnread = Self("chat_marked_unread")

    // MARK: Sessions (meeting to train together)

    static func sessionProposed(sport: String?, options: Int) -> Self {
        .init("session_proposed", ["sport": sport, "options_count": options])
    }
    static func sessionCountered(options: Int) -> Self { .init("session_countered", ["options_count": options]) }
    static func sessionResponded(_ response: SessionResponse) -> Self { .init("session_responded", ["response": response]) }
    static let sessionCancelled = Self("session_cancelled")
    static func sessionActionFailed(_ action: String, reason: String) -> Self {
        .init("session_action_failed", ["action": action, "reason": reason])
    }
    static let sessionAddedToCalendar = Self("session_added_to_calendar")

    // MARK: Purchases

    /// `fromScreen`: where it was opened (Discover's undo, Likes, You...).
    static func paywallViewed(_ kind: ProductKind, fromScreen: Screen?) -> Self {
        .init("paywall_viewed", ["kind": kind, "from_screen": fromScreen])
    }
    static func paywallDismissed(_ kind: ProductKind, purchased: Bool) -> Self {
        .init("paywall_dismissed", ["kind": kind, "purchased": purchased])
    }
    static let productsLoadFailed = Self("products_load_failed")
    static func purchaseStarted(_ kind: ProductKind, productID: String) -> Self {
        .init("purchase_started", ["kind": kind, "product_id": productID])
    }
    /// The store confirmed it. Revenue itself comes from RevenueCat's own PostHog integration.
    static func purchaseCompleted(_ kind: ProductKind, productID: String, currency: String?) -> Self {
        .init("purchase_completed", ["kind": kind, "product_id": productID, "currency": currency?.lowercased()])
    }
    static func purchaseCancelled(_ kind: ProductKind, productID: String) -> Self {
        .init("purchase_cancelled", ["kind": kind, "product_id": productID])
    }
    static func purchaseFailed(_ kind: ProductKind, productID: String, problem: String) -> Self {
        .init("purchase_failed", ["kind": kind, "product_id": productID, "problem": problem])
    }
    static func purchaseCredited(seconds: Int) -> Self { .init("purchase_credited", ["seconds_to_credit": seconds]) }
    static func purchasesRestored(found: Bool) -> Self { .init("purchases_restored", ["found": found]) }
    static let restoreFailed = Self("restore_failed")
    static let subscriptionManageOpened = Self("subscription_manage_opened")

    // MARK: Own profile

    /// Which parts changed (codes: `photos`, `bio`, `sports`...), never their content.
    static func profileEdited(fields: [String]) -> Self { .init("profile_edited", ["fields": fields, "fields_count": fields.count]) }
    static func profileEditFailed(_ reason: String) -> Self { .init("profile_edit_failed", ["reason": reason]) }
    /// A picked photo starts its upload (a retry counts again: `retry`).
    static func photoUploadStarted(where place: String, retry: Bool) -> Self {
        .init("photo_upload_started", ["where": place, "retry": retry])
    }
    static func photoUploadFailed(_ reason: String) -> Self { .init("photo_upload_failed", ["reason": reason]) }
    static let photoRemoved = Self("photo_removed")
    static func photoModerated(_ verdict: String) -> Self { .init("photo_moderated", ["verdict": verdict]) }
    static let photoReviewRequested = Self("photo_review_requested")
    static func voiceIntroRecorded(seconds: Int, where place: String) -> Self {
        .init("voice_intro_recorded", ["duration_seconds": seconds, "where": place])
    }
    static func profilePaused(_ paused: Bool) -> Self { .init("profile_paused", ["paused": paused]) }
    static let selfieVerificationStarted = Self("selfie_verification_started")
    static let selfieVerificationSubmitted = Self("selfie_verification_submitted")
    static func selfieVerificationFailed(_ reason: String) -> Self { .init("selfie_verification_failed", ["reason": reason]) }

    // MARK: Safety

    static let userBlocked = Self("user_blocked")
    static let userUnblocked = Self("user_unblocked")
    /// The report's category, never its details.
    static func userReported(_ reason: String) -> Self { .init("user_reported", ["reason": reason]) }
    static func reportFailed(_ reason: String) -> Self { .init("report_failed", ["reason": reason]) }

    // MARK: Settings, permissions, notifications

    static func languageChanged(_ language: String, during: String) -> Self {
        .init("language_changed", ["language": language, "during": during])
    }
    static func permissionRequested(_ permission: Permission, result: PermissionResult, during: String) -> Self {
        .init("permission_requested", ["permission": permission, "result": result, "during": during])
    }
    static func notificationSettingChanged(_ setting: String, enabled: Bool) -> Self {
        .init("notification_setting_changed", ["setting": setting, "enabled": enabled])
    }
    static func pushOpened(_ kind: String) -> Self { .init("push_opened", ["kind": kind]) }
    static func pushReceived(_ kind: String, inForeground: Bool) -> Self {
        .init("push_received", ["kind": kind, "in_foreground": inForeground])
    }
    /// `doc`: `terms`, `privacy`, `community`, `notice`, `sensitive_data`.
    static func legalDocOpened(_ doc: String) -> Self { .init("legal_doc_opened", ["doc": doc]) }
    static func supportContacted(topic: String, signedIn: Bool) -> Self {
        .init("support_contacted", ["topic": topic, "signed_in": signedIn])
    }
    static func shareTapped(_ what: String) -> Self { .init("share_tapped", ["what": what]) }
}

// swiftlint:enable discouraged_optional_boolean function_parameter_count
