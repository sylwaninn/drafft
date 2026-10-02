# Telemetry: crash reporting (Sentry) and product analytics (PostHog)

What the app sends about how it behaves and how it's used, why, and the rules that keep it lawful for
an app that holds sensitive data. The code is in `Drafft/Services/Telemetry/`: `Core/` holds the rules
(no SDK, unit-tested in `DrafftTests/TelemetryTests.swift`), the rest plugs in the two SDKs. The Android
app follows the same plan with the same names (drafft-android `docs/telemetry.md`, PR #44).

## Two services, two jobs

| | Sentry | PostHog |
|---|---|---|
| Job | Reliability: crashes, app hangs, watchdog terminations, MetricKit's hang, CPU and disk diagnostics, unexpected errors, slow requests and uploads, app start, slow and frozen frames, the app's own logs | Product: which features are used, funnels (sign-up, first like, first match, first session, purchase), retention, experiments |
| Region | EU (`*.ingest.de.sentry.io`, enforced by the app and CI) | EU cloud (`https://eu.i.posthog.com`, enforced by the app and CI) |
| Legal basis | Legitimate interest: keeping the service working and safe. Already named in the privacy policy (`/privacy#data`) | Consent for linking events to the account; anonymous audience measurement otherwise (see below) |
| Who | The account's id (Supabase user id), always | The account's id only with consent (`AnalyticsConsent.granted`); a random install id otherwise |
| Never | Screenshots, view hierarchy, session replay, IP address, name, email, phone, message content, other services' URLs | Autocapture of taps, screen autocapture, session replay, surveys, error tracking, the profile's sensitive answers, anything typed |

The app talks to neither SDK directly: everything goes through `Telemetry` (an enum with pluggable
engines, safe from any thread), which applies `PrivacyGuard` and the person's consent first. Without
keys (local builds, unit tests) every call does nothing.

## Identity: who is who, within the GDPR

One pseudonymous id everywhere: the **Supabase user id** (a UUID, lowercased). It is already the
RevenueCat app user id and the id in every backend table, so a Sentry issue, a PostHog person, a
RevenueCat customer and a profile row are the same person for the team, and for nobody else. No name,
email or phone number ever goes with it.

- **Sentry** gets it at every sign-in (`Telemetry.signedIn`, fed by Supabase Auth's
  `authStateChanges` in `TelemetrySession.watchAccount`). Support can open "every crash of this
  account" from a ticket. Signing out clears it.
- **PostHog** gets it only once the person agreed to usage analytics (`identify`). Before that, events
  carry a random id of this install (`personProfiles = .identifiedOnly`: no person profile is created),
  which a sign-out renews. Funnels and retention still work per install.
- A refusal (`denied`) opts PostHog out entirely, persisted by the SDK. Sentry keeps working.
- Withdrawing consent resets PostHog to a fresh anonymous id: nothing that follows links back.

Why consent for PostHog: identified, per-person product analytics reads an identifier from the phone
for a purpose that isn't strictly necessary (ePrivacy article 5(3)), and the CNIL's audience
measurement exemption only covers anonymous statistics. Anonymous mode stays within that exemption as
long as the privacy policy says so and people can object.

### What the app never sends

`PrivacyGuard` checks every property, tag and log line:

- Names on its `forbidden` list are dropped whatever the event: identity and contact (`name`, `email`,
  `phone`, `birthday`, `age`), **sensitive data under GDPR article 9** (`gender`, `interested_in`,
  `orientation`, `lifestyle`, `diet`, `drinks`, `smokes`, `religion`, `health`: together they reveal
  orientation, health or beliefs), what people write or record (`bio`, `message`, `text`, `note`,
  `prompt`, `answer`), location (`latitude`, `neighborhood`...), another person (`target_id`,
  `match_id`...) and secrets.
- Values must be numbers, booleans, or short codes (`^[a-z0-9][a-z0-9_.:-]*$`): a sentence someone
  typed never passes. Enums go as their raw value, a snake_case code.
- Free text that must go (log lines, error messages, breadcrumbs) is scrubbed of emails, phone
  numbers, UUIDs (another person's id), tokens, JWTs and coordinates, and URLs lose their query string.
- A dropped property is a Sentry log line. Unit tests run every event of the catalog through
  `PrivacyGuard.check` and fail on any drop.
- Discover filters send distance and the number of sports, never who someone wants to meet. Sign-up
  sends counts and yes/no (photos, sports, prompts, "answered lifestyle"), never the answers. Reports
  send the category, never the details. Profile edits send which fields changed, never their content.
- PostHog's `beforeSend` and Sentry's `beforeSend`, `beforeBreadcrumb` and `beforeSendLog` apply the
  same rules a last time on the way out.

## Errors: what alerts and what doesn't

`Telemetry.unexpected(error, area, action)` is called in a `catch` that swallows or rethrows a
failure the app didn't expect. Best-effort upkeep written `try?` (cache refreshes, cleaning up a file)
is not reported. It classifies the error (`ErrorKind`, read by `AppErrorClassifier`):

| Kind | Sentry issue? | Example |
|---|---|---|
| `cancelled`, `offline`, `signed_out` | No (breadcrumb) | Airplane mode, a task cancelled, an expired token |
| `refused` | No (breadcrumb) | `daily_like_limit`, a wrong password, a wrong SMS code |
| `rate_limited`, `store_declined` | No (breadcrumb) | HTTP 429, a purchase waiting for a parent |
| `client_contract` | **Yes** | A 4xx without a code: app and server disagree |
| `server` | **Yes** | HTTP 5xx, the SMS provider failing |
| `store_unconfirmed` | **Yes** | The App Store may have charged without RevenueCat confirming |
| `unexpected` | **Yes** | Anything else |

So an issue in Sentry means something needs a fix. A 4xx with a one-word code (`not_found`,
`already_swiped`) is a refusal the server meant, even when the app has no words for it; a 401 is the
session's business. Every non-2xx response from `Backend` is also a Sentry log line (searchable, not
an issue). RevenueCat and Stream unreachable count as offline.

The app's own log lines (`AppLog`, which replaces `os.Logger` and still writes to the device log), by
level: `info` and `notice` are breadcrumbs (they come with the next error report), `error` is a Sentry
log line (searchable, never an issue), `fault` is a Sentry issue (something that should never happen,
like a backend that isn't deployed). `debug` stays on the phone. A cancelled task is never a failure:
`Telemetry.track` drops any event whose `reason` is `cancelled`.

Performance: every `Backend` request is a span (`http.client`, `POST rest/v1/rpc/discover`) with its
status and duration, a child of the running trace or a trace of its own. Lone requests are the most
frequent traces, so production keeps 2% of them and 20% of the others (app start, uploads); staging
and local keep everything. Media uploads (`media.upload`: profile photos, chat media, the selfie) are
timed too. Profiles follow 5% of the sampled traces in production. Sentry's automatic URLSession
tracing, failed-request capture and network breadcrumbs are off: they would record Stream, RevenueCat
and storage URLs (signed links), and turn 5xx into issues the app already classifies.

MetricKit: Sentry's integration sends the hang, CPU and disk diagnostics; `Diagnostics` keeps the daily
metrics on the phone and sends their summary as a Sentry log line.

## The tracking plan

All events live in `AnalyticsEvent` (one static factory per event). Names are `object_action`,
snake_case, past tense. Every event also carries `screen` (the screen on show), and these super
properties: `app_environment` (`production`, `staging`, `local`), `app_language`, `app_phase`
(`welcome`, `onboarding`, `main`), `is_premium`. PostHog adds the app version, OS, device model and
its lifecycle events (`Application Installed`, `Updated`, `Opened`, `Backgrounded`).

Screens (`Screen`, PostHog `$screen`): the tabs, sign-up and the welcome screen (set by `RootView` from
the phase and the tab; it stays on Discover while the tabs are built invisibly under the splash), the gates (location, terms, hold), and every pushed screen and sheet that
matters (`profile_detail`, `chat`, `paywall`, `extras`, `edit_profile`...). `.trackScreen(.x)` on a
view counts it while it's on screen (not while the tabs are hidden); `.trackPaywall(kind)` also sends
`paywall_viewed` (with `from_screen`) and `paywall_dismissed` (with `purchased`).

| Area | Events |
|---|---|
| Account | `account_created`, `sign_up_failed`, `email_confirmed`, `email_code_resent`, `logged_in`, `log_in_failed`, `password_reset_requested`, `password_reset_completed`, `logged_out`, `session_ended`, `account_deleted`, `account_delete_failed`, `email_changed`, `password_changed`, `data_export_requested`, `terms_accepted`, `analytics_consent_changed`, `account_held` |
| Sign-up | `onboarding_step_viewed`, `onboarding_step_completed` (with `skipped`, `seconds_on_step`), `onboarding_step_blocked`, `onboarding_resumed`, `onboarding_completed`, `onboarding_failed` |
| Phone | `phone_code_sent`, `phone_code_failed`, `phone_verified`, `phone_verification_failed` |
| Discover | `deck_loaded`, `deck_load_failed`, `deck_empty_shown`, `profile_swiped` (`like`, `pass`, `super_like`; from the deck or Likes), `swipe_refused`, `swipe_undone`, `daily_like_limit_reached`, `profile_viewed`, `filters_changed`, `boost_started`, `boost_failed`, `voice_intro_played` (`where`: the screen, when a tap starts playback, not for chat voice messages), `icebreaker_answered` (once per card, not on the person's own profile) |
| Likes and matches | `likes_viewed`, `match_created` (`my_swipe`, `their_like`), `match_screen_action`, `unmatched`, `match_ended` |
| Chat | `chat_opened`, `message_sent` (kind, reply, first message, duration), `message_failed`, `message_retried`, `message_reacted`, `message_deleted`, `chat_muted`, `chat_marked_unread` |
| Sessions | `session_proposed` (sport, options), `session_countered`, `session_responded`, `session_cancelled`, `session_action_failed`, `session_added_to_calendar` |
| Purchases | `paywall_viewed` (kind, `from_screen`), `paywall_dismissed`, `products_load_failed`, `purchase_started`, `purchase_completed`, `purchase_cancelled`, `purchase_failed`, `purchase_credited` (`seconds_to_credit`), `purchases_restored`, `restore_failed`, `subscription_manage_opened` |
| Own profile | `profile_edited` (`fields`), `profile_edit_failed`, `photo_upload_started` (`retry`), `photo_upload_failed`, `photo_removed`, `photo_moderated` (`approved`, `refused`, `in_review`), `photo_review_requested`, `voice_intro_recorded` (`duration_seconds`, `where`), `profile_paused`, `selfie_verification_started`, `selfie_verification_submitted`, `selfie_verification_failed` |
| Safety | `user_blocked`, `user_unblocked`, `user_reported` (category), `report_failed` |
| Settings and system | `language_changed`, `permission_requested` (permission, result, during; sent when the system asked or the person is blocked, never for a permission already granted), `notification_setting_changed`, `push_received`, `push_opened`, `legal_doc_opened`, `support_contacted`, `share_tapped` (`what`: `photo` or `video`, from the media viewer) |

Revenue is not computed on the phone: turn on RevenueCat's PostHog integration (purchases, renewals,
cancellations and refunds with their real amounts, under event names like `rc_initial_purchase_event`,
keyed by the same app user id).

### Adding an event

1. Add a factory to `AnalyticsEvent` with typed parameters (enums, numbers, booleans, codes), and the
   event to `testEveryEventPassesThePrivacyGuardUntouched`.
2. Call `Telemetry.track(...)` where the thing happened, preferably in the model (`AppModel`, a
   service) rather than a button: the model knows whether it worked.
3. Add it to the table above, and to the Android app with the same name and properties.
4. Never rename an event or a property: dashboards depend on them. Add a new one.

## Setup

### Keys (`Config/*.xcconfig`, through Info.plist)

| Key | Where to find it |
|---|---|
| `SENTRY_DSN` | Sentry › Project `drafft-ios` › Settings › Client Keys (DSN). EU organisation. Write `https:/$()/...` (an xcconfig reads `//` as a comment) |
| `POSTHOG_API_KEY` | PostHog › Project settings › Project API key (`phc_...`) |
| `POSTHOG_HOST` | `https:/$()/eu.i.posthog.com` |
| `APP_ENVIRONMENT` | `production`, `staging` or `local` (already set) |

Empty values turn the service off. Production and staging share the Sentry project (the `environment`
tag separates them); PostHog uses one project per environment so tests never pollute real numbers.
CI refuses a non-EU host or DSN, and anything shaped like a secret (Sentry auth tokens, PostHog
personal API keys); the app also ignores a non-EU value. gitleaks allows DSNs and `phc_` keys by
value, nothing else.

### Readable stack traces (dSYMs)

An archive runs the "Upload dSYMs to Sentry" build phase: with `sentry-cli` installed
(`brew install getsentry/tools/sentry-cli`) and its token found (`SENTRY_AUTH_TOKEN`, an organization
token, with `SENTRY_ORG` and `SENTRY_PROJECT`, in the environment or `~/.sentryclirc`), it uploads the
dSYMs and the source context. Without them the archive works and says so in a warning; upload later
with `sentry-cli debug-files upload --include-sources <path to the archive's dSYMs>`. In Xcode Cloud, do
the same from a `ci_scripts/ci_post_xcodebuild.sh` with the token as a secret environment variable.

### Sentry project settings

- Security & Privacy: Data Scrubber on, "Prevent storing of IP addresses" on.
- Alerts, at least: a new issue in `production`; an issue's frequency above its baseline; crash-free
  sessions under 99.5% for the latest release; `area:purchase` issues (money is involved) to a
  dedicated channel; the "purchase credited late" message.
- Data retention: the plan's default (90 days) is fine for crash data.

### PostHog project settings

- Region EU, "Discard client IP data" on, GeoIP enrichment kept (country and city only).
- Person profiles: identified only (also set in the SDK).
- Feature flags are not preloaded (each preload is a billed request): turn `preloadFeatureFlags` on
  with the first experiment.
- Data retention: within the CNIL's audience measurement guidance (an identifier lives 13 months at
  most, the data 25 months at most).
- Dashboards to start with: the sign-up funnel (`onboarding_step_viewed` by `step_index`), activation
  (`onboarding_completed` → `profile_swiped` → `match_created` → `message_sent` → `session_proposed`),
  monetisation (`paywall_viewed` by `from_screen` → `purchase_completed`), retention by first week.

### App Store

`Drafft/PrivacyInfo.xcprivacy` declares crash data, performance data and product interaction, and
the analytics purpose of the user id and the device id (the install id). The App Privacy answers in
App Store Connect must say the same: crash data, performance data, other diagnostic data and product
interaction, collected, not used for tracking, linked to the account.

## What remains to do outside this repository

- **Consent switch (first, in the iPhone app):** a switch in You › Privacy & data ("Share usage analytics", off by
  default, with one line on what it means), and optionally a one-time question after sign-up. Its
  words go in the catalog first (WORDING.md), then `TelemetrySession.setConsent` wires it. Until then
  everyone is in anonymous mode.
- **Privacy policy (drafft-web):** add PostHog (EU) to `/privacy#data` with the purpose, the anonymous
  mode, the consent for linking to the account, and how to object; Sentry is already listed.
- **Account deletion (drafft-backend, `delete-account`):** delete the PostHog person and its events
  through PostHog's persons API (found by distinct id = the user id; a personal API key kept
  server-side, never in the app). Sentry keeps events for its retention period (90 days); an erasure
  request within it is handled by deleting the issues and events matching `user.id:<id>`. Data export
  should say that analytics data can be requested too.
