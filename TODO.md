# TODO: app

Backend work lives in `drafft-backend/TODO.md`. Media preparation and upload are ready
(`Drafft/Services/Media`), not wired to screens yet.

## Connect to the backend

- [ ] Add packages: `GoogleSignIn-iOS`, `StreamChat` (low-level client, no UI), `Nuke`, `GRDB.swift`,
      `sentry-cocoa`. (`supabase-swift` is in.)
- [ ] Service protocols (profiles, discover, likes, matches, sessions, safety, media) with two
      implementations: the current mock and Supabase. Views keep talking to `AppModel`.
- [x] Auth: email + password on Supabase Auth (`Backend`, session in the Keychain, refreshed by the SDK), sign-up
      with email confirmation (`ConfirmEmailView`), log in, reset password by a 6-digit code (`ResetPasswordView`, no
      link: every auth email carries a code), session restored at launch, change email/password,
      delete account (`delete-account`), sign out (unregisters the push token).
- [x] Sign-up and profile on the server (`ProfileSync`): sign-up sends the answers, sports, prompts, voice intro,
      photos (in order) and the blurred position, then `complete_onboarding` (its refusals shown under the button);
      Edit profile saves the same way (birthday fixed after sign-up); You is read back from the server at sign-in.
      Photos and voice intros on the server are URLs (`app-config` gives the media base; `RemotePhoto`, audio cached).
- [ ] Production: enable the Send SMS hook (auth-sms, Twilio) before release: the phone step always sends real codes.
- [ ] Sign in with Apple and Google (id token → `signInWithIdToken`): off the welcome screen until then.
- [ ] Map RPC error `hint` codes (`daily_like_limit`, `no_super_likes`, `underage`, `photo_required`…) to
      UI copy; disabled validate buttons carry the reason.
- [ ] Realtime: subscribe to `user:<id>` (like, match, match_ended, session, media).
- [ ] Push: register for APNs, `register_push_token(token, environment)` with `sandbox` for Xcode builds and
      `production` for TestFlight / App Store; `unregister_push_token` on sign-out; route taps (`match`,
      `session`, `tab`). (`aps-environment` stays `development` in the file: archiving for TestFlight re-signs it as production.)
- [ ] Remote pushes like the demo ones (title "drafft", sentence from `NotificationText`, sender photo as
      thumbnail): a Notification Service Extension that downloads the photo from the CDN and attaches it.
- [x] Weekly boost (drafft tempo): the server credits it (first one on subscribing, then weekly, `wallets.weekly_boost_at`)
      and pushes it (`kind: weekly_boost` opens Discover). The app only reads `wallets` (no local crediting or notification).
- [ ] Notification previews off: the service extension must replace the message text (Stream pushes include
      it) with `NotificationText.body(.message…)`. (The settings themselves are saved on the profile and the
      phone, read back at launch: `NotificationService.loadSettings`.)
- [x] Reactions over Stream: `sendReaction(type: <the emoji>, enforce_unique: true)`, only on the other person's
      messages; `deleteReaction` to remove. The reaction push comes from the backend (`stream-webhook`), with the
      message id as collapse id and `match` to open the chat.
- [x] Stream push: `addDevice` with push provider `drafft-apn` (TestFlight, App Store) or
      `drafft-apn-dev` (Xcode builds).
- [ ] Location: reduced-accuracy CoreLocation → `set_location` at launch and on significant change.

## Media (pipeline ready, to wire)

- [ ] Profile video: `MediaUploads.video` (poster uploaded first) → `add_profile_media(kind: video,
      duration, poster_key)`.
- [x] Chat photos and videos: `purpose: .chatPhoto / .chatVideo`, `VideoCompressor.Settings.chat`, then a
      Stream `drafft_media` attachment carrying the object's key (links signed on display, `media_urls`).
- [ ] Background relaunch: forward `application(_:handleEventsForBackgroundURLSession:completionHandler:)`
      to `MediaUploader.shared.handleEventsForBackgroundSession`.
- [ ] Persist the upload queue (GRDB): if the app is killed mid-upload, the file still arrives but the
      `add_profile_media` step is lost. Store pending uploads and finish registration at next launch.
- [ ] Upload states in the UI: progress, retry, "Checking your photo" while moderation is pending,
      rejected state.
- [ ] Test on device with real iPhone footage: 4K60 HDR / Dolby Vision (tone mapping to SDR), Live
      Photos, ProRAW, very long videos. The harness only covered synthetic 1080p SDR and JPEG.
- [ ] Compression speed on older supported iPhones (A13); show progress when transcoding takes over 1 s.

## Speed on screen

- [ ] ThumbHash **decoder** (`thumbHashToRGBA`) to draw placeholders; the encoder is done.
- [ ] Nuke pipeline: disk + memory cache, CDN sizes via `/cdn-cgi/image/width=…,quality=80/<key>`,
      decoding at display size, prefetch the next 3 cards' photos.
- [ ] Profile videos and voice intros: download the whole file to a disk cache while the card is next
      in the deck, then play the local file.
- [ ] GRDB cache: cards with `cardVersion`, last discover batch, matches, sessions. Show cached data at
      launch, refresh with `get_cards(p_known:)`.
- [ ] Deck refill: fetch the next `discover` batch when 5 cards are left.
- [ ] Warm the connection at launch (first request to the API and media hosts).

## Chat (Stream)

- [x] `stream-token` at launch and on expiry; connect the low-level client.
- [x] Map custom messages: `session` (load the row, live status from Realtime), `icebreakerReply`,
      `photoReply`, `superLikeNote`, `text` openers.
- [x] Optimistic sends, read receipts, typing, reactions, replies, mute (Stream channel mute).
- [x] Voice messages as Stream attachments (AAC 48 kb/s mono, already the recorder's setting).

## Money and trust

- [ ] RevenueCat SDK (`purchases-ios`): configure with the public key `appl_tGPiuiBrncvrUfYkkFAGQzOmQEF`
      (App Store app `appebec589867`, project `proj3dc1aebd`), entitlement `drafft_tempo`,
      offering `default` ($rc_monthly, $rc_six_month, $rc_annual). Packs: buy the store products
      directly. Done in the app: `Purchases.logIn(<Supabase user id, lowercased>)` at every sign-in and
      restored session, purchases disabled until then, `logOut` on sign-out and account deletion; balances
      and drafft tempo read from `wallets` (Realtime `wallet`, back at the front, after a purchase).
      Left: a sandbox purchase tested end to end (App Store, RevenueCat, webhook, wallet) before any submission.
- [ ] Phone verification with the real provider in production (see the Send SMS hook above).
- [ ] Sentry: crashes, hangs, slow frames, failed uploads.
