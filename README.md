<div align="center">

<img src="docs/sticker.png" alt="drafft for iOS" width="480">

**Meet someone who gets your rhythm.**

The iPhone app of drafft, the dating app for people who train.<br>
Profiles lead with how someone moves, and a match is an invitation to propose a session together.

[![app](https://github.com/sylwaninn/drafft-ios/actions/workflows/app.yml/badge.svg?branch=staging)](https://github.com/sylwaninn/drafft-ios/actions/workflows/app.yml)
[![pr](https://github.com/sylwaninn/drafft-ios/actions/workflows/pr.yml/badge.svg)](https://github.com/sylwaninn/drafft-ios/actions/workflows/pr.yml)
![iOS](https://img.shields.io/badge/iOS-26%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?logo=swift&logoColor=white)
![Languages](https://img.shields.io/badge/languages-7-2EA44F)
![License](https://img.shields.io/badge/license-proprietary-lightgrey)

[Product](#product) · [How it works](#how-it-works) · [Getting started](#getting-started) · [Release](#release) · [Docs](#documentation)

</div>

## Product

drafft is the dating app for people who train. Sports come first on a profile, and when two people like each
other, drafft invites them to propose a session. A match promises nothing on its own: the proposal is the next
step, and the people decide.

| Area | What the app does |
|---|---|
| **Sign up** | Email and password, phone check by SMS code, consents recorded on the server |
| **Profile** | Photos, sports with how often, a voice intro, an icebreaker others can react to |
| **Discover** | Nearby profiles filtered by sport, likes, super likes, boosts |
| **Matches and sessions** | Mutual likes, session invites, calendar events |
| **Chat** | Text, photos, videos, voice messages, replies and reactions |
| **drafft tempo** | The paid tier (undo, see who likes you); boosts and super likes in packs |
| **Safety** | Report and block, moderation, selfie check, help center |

Users, principles and legal rules: [PRODUCT.md](PRODUCT.md). Visual system: [DESIGN.md](DESIGN.md).
Every word people read: [WORDING.md](WORDING.md).

## How it works

A native iPhone app on the drafft backend. The server is the source of truth: the app shows what it last knew
at once, then reads the server again and listens to the account's Realtime channel, so every screen stays live.

```mermaid
flowchart LR
  App["iPhone app<br/>SwiftUI screens,<br/>AppModel, services"]
  App --> Cache[("Local cache<br/>per account, on the phone")]
  App <--> Supabase["Supabase, drafft-backend<br/>Auth, RPCs,<br/>Edge Functions, Realtime"]
  App --> R2[("Cloudflare R2<br/>uploads, presigned PUT")]
  App --> Worker["media Worker<br/>photos and videos,<br/>signed GET"]
  App <--> Stream["Stream Chat<br/>messages, reactions"]
  Push["Apple Push<br/>Notification service"] --> App
  App --> RevenueCat["RevenueCat<br/>App Store purchases"]
  App --> Telemetry["Sentry, PostHog<br/>crashes and events, EU"]
```

### The app

- **Start.** `DrafftApp` starts telemetry, diagnostics (MetricKit), the image pipeline and RevenueCat, then
  `RootView` shows welcome, sign-up or the five tabs (Discover, Likes, Sessions, Chats, You). The tabs are built
  once, ahead of time, under the splash.
- **State.** One `@MainActor @Observable` `AppModel`, split by domain into `AppModel+*.swift` (account,
  Discover, matches, likes, wallet, sessions, safety), passed to every screen through the environment. The
  account hold and the location request each cover the app in their own window.
- **Folders.** `Drafft/App` (entry), `Features/` (screens by area), `DesignSystem/` (DESIGN.md in code),
  `Services/` (model and services), `Models/` (value types), `Resources/` (catalogs, fonts, assets).

### Backend link

- **Client.** supabase-swift for Auth (the session in the Keychain) and Realtime; RPCs, table reads and Edge
  Functions are plain `URLSession` calls with the publishable key and the session's token.
- **Errors.** The backend answers a stable code (`hint` for database functions, `code` for Edge Functions);
  `ServerMessage` turns it into words, never the raw reply. `moderated` opens the hold screen.
- **Edge Functions called.** `media-upload-url`, `stream-token`, `chat-media`, `phone-code`, `purchase-sync`,
  `delete-account`, `device-check` (DeviceCheck token, at launch and sign-in), `support` (Turnstile when signed
  out), `app-config`.

### Live updates

The app joins the private Realtime topic `user:<id>`, rejoins with a backoff of 2 to 60 s, and rebuilds the
channel after 15 s down.

| Event | What the app does |
|---|---|
| `like`, `match`, `match_ended` | reads likes or matches again, closes an ended match |
| `session` | updates the session, its chat card and its calendar event |
| `media` | applies a photo's moderation verdict |
| `wallet` | reads the balance again (boosts, super likes, drafft tempo) |
| `profile`, `moderation` | reads the account again; a hold covers the app |
| `session_revoked` | signs out if this device's session ended elsewhere |

On each join and each return to the foreground, it also reads the account, the wallet, sessions and Discover
again, and resumes any purchase still being credited.

### Media

- **Upload.** `media-upload-url` returns a ticket, then the file goes straight to Cloudflare R2 with a presigned
  PUT from a background `URLSession` (two retries; a new ticket on 403). Photos are resized to 2048 px, stripped
  of EXIF and GPS, and get a ThumbHash; videos are re-encoded to HEVC 720p.
- **Profile photos.** A picked photo is a draft (`add_profile_media`), checked by the backend; its verdict
  arrives as a `media` event. Save publishes the set (`save_profile_media`); unsaved drafts are deleted.
- **Display.** Cards carry signed links of about an hour; Nuke renews a link about to expire through
  `media_urls`, asks the media Worker for the width it draws (`&w=` among 160, 320, 640, 1080, 1440), decodes at
  frame size and shows the ThumbHash meanwhile. Caches: 300 MB on disk, up to 256 MB in memory, keyed by photo
  and width, never by signature. Six downloads at once, two on a slow network.
- **Chat media.** Photos and videos sent in a chat are delivered first, then checked silently (`chat-media`).
- **Blurred likes.** Without drafft tempo, Likes shows a ThumbHash, then a blurred copy made by the server.

### Chat

Stream Chat's low-level client, every screen drafft's own, with Stream's offline store. `stream-token` gives the
token (asked again whenever Stream needs one). One `messaging` channel per match, named by the match id; the
list shows the person's channels that aren't frozen. Photos, videos, voice messages and files are attachments
that carry a media key, never a link. Session cards, super like notes and replies to an icebreaker or a photo
come from the backend as messages. Texts written offline wait for the connection.

### Push notifications

- **Tokens.** The APNs token is registered with the backend (`register_push_token`, with the build's sandbox or
  production environment) and with Stream (push provider `drafft-apn`, or `drafft-apn-dev` in the sandbox).
- **Senders.** The backend pushes likes, matches, sessions and reminders, photo refusals, account notices and
  the weekly boost; Stream pushes chat messages. While the app is open, a message from another chat shows as a
  local notification, and a photo refusal or account notice applies live instead of showing a banner.
- **Taps.** A tap opens the chat, Discover (a boost), Sessions or the refused photo. Notification settings
  (`notify_*`) are saved on the profile, which the backend reads before sending.

### Purchases

RevenueCat on the App Store, logged in with the Supabase user id. Offerings: `default` (drafft tempo), `boosts`,
`super_likes`; entitlement `drafft_tempo`. Once the App Store confirms, `purchase-sync` credits the purchase on
the server and returns the new balance; until it answers, the app retries (2, 5, 15, 60 s, then every 5 minutes)
and keeps the purchase pending for the account. Nothing is credited on the phone. The **Drafft** scheme runs
with a local StoreKit configuration (`StoreKit/Drafft.storekit`).

### Location and calendar

- **Location.** Reduced accuracy, while in use, required to use the app. A reading is blurred to the centre of a
  cell of about 1 km before `set_location` or `area_at`. Outside France or offline, the app names the area
  itself.
- **Calendar.** With access granted, a session becomes an event that follows it (moved, removed when
  cancelled) and never overwrites what the person edited.

### Telemetry

- **Sentry** (EU only): crashes, hangs, MetricKit, unexpected errors and traces (20 % in production). No
  screenshots, view hierarchy, replay, personal data or IP. dSYMs upload when a store build is archived.
- **PostHog** (EU only): the app's own events and screens, no autocapture or replay. Events stay anonymous
  until the person grants analytics consent, and stop if they refuse.
- **PrivacyGuard** drops what people typed, sensitive answers, locations and other people's ids before anything
  leaves the phone. Events and rules: [docs/telemetry.md](docs/telemetry.md).

### On the phone

- **Cache.** `LocalCache` (GRDB): one SQLite file per account, excluded from backups: profile, matches, likes
  (with drafft tempo), the Discover deck (under 45 minutes old, same filters). Shown first, then replaced by
  the server's answer. Erased at sign-out and account deletion.
- **Stream's offline store** for chats; Nuke's disk cache for images.
- **Selfie check**, only when moderation asks: the front camera with Vision face detection, the photo goes to
  the backend's `verification-selfies` storage, then `submit_selfie`.

### Built with

| Layer | Choice |
|---|---|
| UI | SwiftUI, iOS 26 (Liquid Glass), iPhone only |
| Language, project | Swift 6 with strict concurrency; [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) |
| Backend | [supabase-swift](https://github.com/supabase/supabase-swift) |
| Chat | [Stream Chat](https://github.com/GetStream/stream-chat-swift), low-level client |
| Purchases | [RevenueCat](https://github.com/RevenueCat/purchases-ios) |
| Images, cache | [Nuke](https://github.com/kean/Nuke), ThumbHash; [GRDB](https://github.com/groue/GRDB.swift) |
| Phone numbers | [PhoneNumberKit](https://github.com/marmelroy/PhoneNumberKit) |
| Telemetry | [Sentry](https://github.com/getsentry/sentry-cocoa), [PostHog](https://github.com/PostHog/posthog-ios) |

Dependencies are pinned in `project.yml`, with the reason next to each one.

## Getting started

Needs Xcode 26, `brew install xcodegen swiftlint`, and for the local backend Docker and the Supabase CLI.

```sh
git clone git@github.com:sylwaninn/drafft-ios.git      # next to drafft-backend
cd drafft-ios && git config core.hooksPath .agents/git-hooks

(cd ../drafft-backend && supabase start)               # local backend
scripts/local-backend.sh                               # --device for an iPhone on the same Wi-Fi
xcodegen generate && open Drafft.xcodeproj             # scheme "Drafft Local", then Run
```

> [!IMPORTANT]
> Work on **Drafft Local**. Every scheme shares the bundle id `so.drafft.app`: installing another one replaces
> the local app and sends real actions to staging or production.

| Scheme | Backend | Home screen name | Telemetry |
|---|---|---|---|
| **Drafft Local** | Supabase on your Mac, staging services | drafft local | off |
| **Drafft Staging** | Supabase branch `staging` | drafft β | `staging` |
| **Drafft** | production | drafft | `production` |

Each scheme reads `Config/<Name>.xcconfig`: public client keys only, CI refuses anything shaped like a secret.
Branches, commits, checks and pull requests: [CONTRIBUTING.md](CONTRIBUTING.md).

## Release

`main` is production and moves only through **Actions > release**: with `staging` green, it fast-forwards
`main`, tags the next `vX.Y.Z` from the pull request titles and publishes a GitHub release. Store builds are
archived by hand from the tag, with the Sentry upload token set for dSYMs
([docs/telemetry.md](docs/telemetry.md#readable-stack-traces-dsyms)).

## Localization

English (source), French, Spanish, German, Italian, European Portuguese and Dutch, picked in the app, not from
the phone. Strings live in `Drafft/Resources/Localizable.xcstrings`, the catalog both drafft apps share; text
built in code goes through `L("…")`. Any change to what people read starts with [WORDING.md](WORDING.md).

## Security

No secret in this repository: `Config/` holds public client keys only, allowlisted by value in
[`.gitleaks.toml`](.gitleaks.toml). The privacy manifest is [`Drafft/PrivacyInfo.xcprivacy`](Drafft/PrivacyInfo.xcprivacy).
Report a vulnerability privately through
[security advisories](https://github.com/sylwaninn/drafft-ios/security/advisories/new), never in an issue.

## Documentation

| Document | Read it when you |
|---|---|
| [PRODUCT.md](PRODUCT.md) | need the users, the principles, the privacy and legal rules |
| [DESIGN.md](DESIGN.md) | touch anything on screen |
| [WORDING.md](WORDING.md) | write any text people read, in any language |
| [CONTRIBUTING.md](CONTRIBUTING.md) | open a pull request: branches, commits, signing, checks |
| [docs/telemetry.md](docs/telemetry.md) | add an event, a screen, an error or an alert |
| [docs/store-screenshots](docs/store-screenshots/README.md) | produce App Store screenshots |
| [scripts/icons](scripts/icons/README.md) | add or change an icon |
| [AGENTS.md](AGENTS.md) | run a coding agent on this repository |

## Related repositories

| Repository | Role |
|---|---|
| [drafft-android](https://github.com/sylwaninn/drafft-android) | Android app |
| [drafft-backend](https://github.com/sylwaninn/drafft-backend) | Supabase, Edge Functions, media and support Workers |
| [drafft-web](https://github.com/sylwaninn/drafft-web) | getdrafft.com and the legal pages the app opens |
| [drafft-sophros](https://github.com/sylwaninn/drafft-sophros) | moderation and support dashboard |

## License

Proprietary. Copyright © 2026 the drafft authors. All rights reserved. No permission is granted to use, copy,
modify or distribute this code without written consent.
