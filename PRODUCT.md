# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

SwiftUI, iOS 26 minimum (Liquid Glass available), project generated with XcodeGen. Third-party dependencies allowed (Swift Package Manager) when proven robust and scalable. Backend: Supabase (drafft-backend), chat on Stream, purchases on RevenueCat; Discover and chats still show sample people until they're wired to it.

## Users

Active urban adults, 25–40, who train 2–5 times a week (run clubs, gyms, padel, climbing, cycling, swimming). They are single, time-poor, and already structure their week around sessions. Their job: meet someone compatible without spending evenings on dead-end chat; sport is both a filter and a shared language.

## Product Purpose

Drafft is a sports dating app. Its distinctive mechanism: the first date is a training session together. A match is not an invitation to chat forever; it is an invitation to propose a session (sport, place, time, level). Success = matches that turn into a real session within days.

## Positioning

Where swipe apps end at "it's a match", Drafft continues to "Tuesday 7am, 8 km, Canal Saint-Martin". Profiles lead with how someone moves (sports, level, weekly rhythm, preferred slots), not just photos. Reference in the category: bpm.so.

## Operating Context

Used on the go: between sessions, after a workout, on transit. One-handed, often outdoors in daylight. Chat is the core loop and must feel instant: text, photos, video, voice messages.

## Capabilities and Constraints

- Sign up / sign in: email + password credentials (Sign in with Apple and Google to come).
- Profile: photos, sports with how often you do each, a voice intro, and an interactive icebreaker ("joke"/prompt) that the viewer can react to.
- Discovery of profiles, matching, proposing a session.
- Messaging: text, photo, video, voice message (no file attachments); must feel ultra-responsive (optimistic sends, instant feedback).
- Accounts, profiles, Discover, chats and moderation run on the backend. No demo mode or test shortcut ships in the app.
- UI languages: English (source), French, Spanish, German, Italian, European Portuguese, Dutch. Picked in the app (sign-up, You › Language), not from the phone. Strings live in `Drafft/Resources/Localizable.xcstrings`; text built in code goes through `L("…")`.

## Privacy and legal

- **The legal pages live on getdrafft.com, never in the app.** Terms of use (the community guidelines are their `#community` section), privacy policy and legal notice, in the 7 languages: English at `/terms`, `/privacy`, `/legal`, the others under their language (`/fr/terms`, `/de/privacy`), with the same section anchors in every language. Sources: the drafft-web repository. `LegalDoc` builds the address in the app's language, with `?lang=<code>` (English included) because the pages otherwise switch to the browser's language, which in the in-app browser is the phone's, not the app's. It opens it in the in-app browser (`openURL(_:prefersInApp:)`): from the sign-up consent and `TermsConsentView` (with the privacy policy's `#sensitive-data` section), the paywall, the drafft tempo sheet and You › Help › Terms & privacy policy. The app keeps no copy of the texts, and any copy that states a fact about data, deletion or billing must say what these pages say.
- **Consent, recorded on the server.** The ground rules step of sign-up asks two separate, unchecked consents (`ConsentChecks`): the terms (18 or older, terms of use, privacy policy, community guidelines), and the use of sensitive data (gender, the genders someone wants to see, lifestyle answers, which can reveal sexual orientation, health or beliefs; the privacy policy bases them on explicit consent, linked at `/privacy#sensitive-data`). Both are required: drafft can't work without the gender. Continue records them with `accept_terms(p_version, p_sensitive_consent)` (`TermsConsent.version`, an ISO date; `TermsConsent.isCurrent` is the one version rule), which fills `terms_version`, `terms_accepted_at` and `sensitive_consent_at` on the profile; `complete_onboarding` refuses a sign-up without them (`terms_required`). An account onboarded without them, or on older terms, gets `TermsConsentView` at each open until it accepts, after the location gate: it can only accept, or delete the account. The gate (`TermsConsent.Gate`) is unknown until a read says: only a fresh read of the profile asks, a cached "accepted" is trusted (the consent is only withdrawn by deleting the account), and a failed read is logged and retried until one succeeds. A backend without the columns (drafft-backend #48 not deployed) is read without them and leaves the gate unknown. If `complete_onboarding` still says `terms_required`, sign-up goes back to the rules step to record it again. Withdrawing the consent means deleting the account (You › Privacy & data › Sensitive data consent); lifestyle answers can be cleared on their own in Edit profile. A new version of the terms: bump `TermsConsent.version`, and everyone is asked again.
- **On the iPhone:** the login (Supabase session, in the Keychain); one cache per account (`LocalCache`, SQLite: own profile, matches, sessions, the last Discover cards, likes), excluded from backups; the chat's offline copy (Stream: the latest messages of each chat); images and voice files already shown (disk caches); the sign-up answers so far, per account, until sign-up ends (`OnboardingStore`); settings (language, Discover search, notification settings, the calendar events of sessions). Signing out or deleting the account removes the cache and the chat's copy. MetricKit diagnostics stay on the phone for now (the last 30). The privacy policy's diagnostics (`/privacy#data`, Sentry among the providers) describe the crash and error reports to come with Sentry, which the app doesn't send yet. The exact location never leaves the phone: it is blurred to a cell of about 1 km first.
- **Permissions, each asked when it's needed:** location, While Using only and required (profiles near you; reduced accuracy, sent at sign-up and again only when the server has none on file); notifications (an optional sign-up step); camera, microphone and photo library (photos, videos, voice messages, the voice intro, the selfie moderation may ask for); calendar (only for the sessions you add, kept up to date and removed if cancelled). Never contacts, health data or tracking.
- **Export and deletion:** You › Privacy & data › Export my data: the server emails a download link, usually within 24 hours, valid 7 days, one request at a time. You › Delete account: immediate. Deleting doesn't cancel drafft tempo (billing belongs to the App Store). What the server erases and what it keeps afterwards, and for how long, is in drafft-backend's README, "Privacy and data retention".

## Brand Commitments

- Name: drafft, always lowercase (app name included), set one weight heavier than the sentence around it. Paid tier: drafft tempo, both lowercase, "tempo" in the accent colour.
- Visual system pinned by the user: DESIGN.md (Wise-inspired: one accent, near-black ink, heavy 900 display, 24pt radius). The accent is violet `#7D70FD` for now (lime `#9fe870` was the original); the page tone follows it (a cool grey touched with violet, `#EDECF2`, with violet). Binding.

## Evidence on Hand

No real users, testimonials, photos, or metrics. All people, photos, and conversations in the demo are synthetic placeholders and must be replaced before any public use. Do not invent user counts, match rates, or press.

## Product Principles

1. Move, then talk: every flow nudges toward a real shared session.
2. Profiles show how someone lives, not only how they look.
3. Chat is instant: no spinner between tap and feedback.
4. Low-pressure first contact: icebreakers do the awkward part.
5. Native iPhone conventions first; brand lives in color, type, and motion.
6. Never leave people guessing what to do next: the validate action is always on screen, disabled until it can run (the screen itself says what's missing, not a line under the button).
7. Always live: whatever the server changes (balance, holds, photo decisions, likes, matches, sessions) reaches the screen at once, over the account's Realtime channel, and is read again on return to the foreground or after a reconnection. Nothing waits for a relaunch or a pull to refresh.
8. One language per person: everything sent to someone (push, email, SMS, support reply, cancellation) is in their app's language (the 7 languages of the app), with the same phrases as the app.

## Accessibility & Inclusion

Dynamic Type, VoiceOver labels on all controls and media, Reduce Motion respected, 44pt touch targets. Inclusive gender/orientation options in onboarding (not yet specified in detail; open decision).
