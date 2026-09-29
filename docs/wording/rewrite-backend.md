# Réécriture backend : push, emails, SMS, produits (drafft-backend + push de l'app)

Tableaux détaillés (en anglais, EN / FR) produits pendant la réécriture. Les décisions listées sont reportées dans [WORDING.md §11](../../WORDING.md#11-decision-log). Dans les tableaux, « · » sépare seulement le titre et le corps d'un push, et ⎵ marque une espace insécable.

## Decisions applied everywhere (to add to the WORDING.md decision log)

1. **Push structure.** The title is the person's name when someone did something: match, message, reaction, session. Otherwise the title is the event: "New like", "In an hour", "Session cancelled". It's never "drafft", because iOS already shows the app name above the notification. The body is one sentence that doesn't repeat the title. Push titles are labels, so they have no full stop. Bodies end with a full stop, except when they end with the session name: that can be the person's own note, question mark included.
2. **The brand's voice in FR:** the subject pronoun is « on » (« On a revu ta photo », « On te répond… »). Never « nous » as a subject. « Nous » as an object stays allowed when there's no other option (« si tu nous réécris »). « L'équipe drafft » only names the team (the title of the support reply). « Notre équipe » and « nos règles » become « les règles de drafft ».
3. **Emails:** the title repeats the subject, with a full stop. The last line (note) is the only next step. Subjects are ≤ 45 characters (tested). Auth emails keep the subject "{code} is your code" for iOS autofill. The line before the code still ends on "code", and no other line uses that word.
4. **Empty name:** it becomes `someone` / « Quelqu'un » as the title, on the server, in the app and in the Stream template. Never an empty title.

## 1. Push (server `texts.ts` = app `NotificationText.swift`)

| Location | Current text (EN / FR) | New text (EN / FR) | Rationale |
|---|---|---|---|
| All pushes, title (`pushTitle`, `NotificationText.title`) | drafft / drafft | Name, or the event (see below) | WORDING.md Push: title = name or event. "drafft" duplicated the app name that iOS already shows |
| `matchCreated` | It's a match with ${name}! Suggest a first session. / C'est un match avec ${name}⎵! Propose-lui une première séance. | **${name}** · It's mutual: propose a first session. / **${name}** · C'est réciproque⎵: propose une première séance. | Cliché banned (5.3), "!" banned, single verb "propose". Same variant as the app screen ("Ihr mögt euch beide", "Es mutuo", etc.) |
| `likeReceived` | Someone liked your profile / Quelqu'un a liké ton profil | **New like** · Someone liked your profile. / **Nouveau like** · Quelqu'un a liké ton profil. | Event title. It stays anonymous (Likes are blurred for free accounts). Full stop added |
| `superLikeReceived` | Someone sent you a super like / Quelqu'un t'a envoyé un super like | **New super like** · Someone sent you a super like. / **Nouveau super like** · Quelqu'un t'a envoyé un super like. | Same. Lowercase super like, as in the lexicon |
| `sessionChanged.proposed` | ${n} suggested a session: ${t} / ${n} te propose une séance⎵: ${t} | **${n}** · Proposed a session: ${t} / **${n}** · Te propose une séance⎵: ${t} | Single verb propose (the EN "suggested" was a second verb). The name moves to the title |
| `sessionChanged.accepted` | ${n} is in: ${t} / ${n} a accepté⎵: ${t} | **${n}** · Confirmed the session: ${t} / **${n}** · A confirmé la séance⎵: ${t} | Matches the app's "Session confirmed" / « Séance confirmée » |
| `sessionChanged.declined` | ${n} can't make it: ${t} / ${n} ne peut pas venir⎵: ${t} | **${n}** · Can't make it this time: ${t} / **${n}** · Ne peut pas cette fois-ci⎵: ${t} | Softer, echoes the app's "Not this time" button, no guilt |
| `sessionChanged.cancelled` | ${n} cancelled: ${t} / ${n} a annulé⎵: ${t} | **${n}** · Cancelled the session: ${t} / **${n}** · A annulé la séance⎵: ${t} | Says what was cancelled |
| `sessionAutoCancelled` (no time) | Your session was cancelled. / Ta séance a été annulée. | **Session cancelled** · The session invite no longer stands. / **Séance annulée** · La proposition de séance ne tient plus. | It's a proposal with several times: lexicon "session invite" / « proposition de séance ». Stays neutral |
| `sessionAutoCancelled` (with time) | Your session on ${day} at ${time} was cancelled. / Ta séance du ${day} à ${time} a été annulée. | **Session cancelled** · Your session on ${day} at ${time} won't go ahead. / **Séance annulée** · Ta séance du ${day} à ${time} n'aura pas lieu. | Useful fact (the date) in the body. Avoids the title/body repetition |
| `sessionReminderEvening` | Tomorrow at ${time}: ${session}. Pack your kit tonight. / Demain à ${time}⎵: ${session}. Prépare ton sac ce soir. | **Tomorrow at ${time}** · With ${name}: ${session} / **Demain à ${time}** · Avec ${name}⎵: ${session} | Title = event + time. Body = who and which session (useful fact). "Pack your kit" dropped: British, and odd for yoga or a walk. With no name, the body is the session alone |
| `sessionReminderHour` | In an hour: ${session}. See you there! / Dans une heure⎵: ${session}. À tout à l'heure⎵! | **In an hour** · With ${name}: ${session} / **Dans une heure** · Avec ${name}⎵: ${session} | "!" banned. "See you there" was false (drafft isn't coming) |
| `weeklyBoost` | Your weekly boost is here. Use it anytime: 30 minutes at the top of decks nearby. / Ton boost de la semaine est là. Utilise-le quand tu veux⎵: 30 minutes en tête des profils près de toi. | **Your weekly boost** · Use it anytime: 30 minutes up front for people near you. / **Ton boost de la semaine** · Utilise-le quand tu veux⎵: 30⎵minutes en tête des profils près de toi. | One sentence. The "decks" jargon is gone (the app says "up front") |
| `photoRefused` | One of your photos wasn't approved. Tap to see why. / Une de tes photos n'a pas été validée. Touche pour savoir pourquoi. | **Photo not approved** · See why one of your photos can't go on your profile. / **Photo non validée** · Découvre pourquoi une de tes photos ne peut pas aller sur ton profil. | « Touche pour » was a literal translation. Picks up the app screen's phrasing ("can't go on your profile") |
| `moderationPush.restored` | Your account is open again. Everything is in order. / Ton compte est de nouveau ouvert. Tout est en ordre. | **Check done** · Your profile is visible again, and your chats are where you left them. / **Vérification terminée** · Ton profil est de nouveau visible, et tes discussions t'attendent là où tu les as laissées. | Answers the app's "We're checking your account." screen. "Everything is in order" was administrative |
| `moderationPush.reopened` | We've looked again and reopened your account. Welcome back. / Nous avons réexaminé ton compte et l'avons rouvert. Content de te revoir. | **Account reopened** · We took another look: your account is open and your profile visible again. / **Compte rouvert** · On a réexaminé ton compte⎵: il est rouvert et ton profil de nouveau visible. | « Content de te revoir » is masculine (5.4). « Nous » becomes « on » |
| `moderationPush.selfieApproved` | Your selfie is verified. Your account is open again. / Ton selfie est validé. Ton compte est de nouveau ouvert. | **Selfie verified** · Your profile is visible again, and your chats are where you left them. / **Selfie validé** · (same as restored) | Event title, useful consequence in the body |
| `moderationPush.selfieRequested` | We need a quick selfie to confirm it's you. Tap to take it. / Nous avons besoin d'un selfie rapide pour confirmer que c'est bien toi. Touche pour le prendre. | **Selfie check** · Take a quick selfie so we can confirm it's you. / **Vérification par selfie** · Prends un selfie rapide pour qu'on confirme que c'est bien toi. | One sentence, verb first. « on » instead of « nous ». « Touche pour » removed |
| `moderationPush.selfieRetry` | We couldn't confirm it's you from your selfie. Tap to take a new one. / Ton selfie ne nous a pas permis de confirmer que c'est bien toi. Touche pour en prendre un nouveau. | **Selfie check** · We couldn't confirm it's you from that selfie: take a new one. / **Vérification par selfie** · On n'a pas pu confirmer que c'est bien toi avec ce selfie⎵: prends-en un nouveau. | Error: what happened, then one way out, no blame |
| `reaction` (no text) | ${name} reacted ${emoji} to your message / ${name} a réagi ${emoji} à ton message | **${name}** · Reacted ${emoji} to your message. / **${name}** · A réagi ${emoji} à ton message. | Name as the title. The emoji is the person's reaction, not ours |
| `reaction` (with text) | ${name} reacted ${emoji} to: “${t}” / ${name} a réagi ${emoji} à⎵: «⎵${t}⎵» | **${name}** · Reacted ${emoji} to “${t}” / **${name}** · A réagi ${emoji} à «⎵${t}⎵» | The colon was pointless. Guillemets with NBSP (the server was missing them) |
| `messageSent` (Stream, previews off) | sent you a message / t'a envoyé un message | **${name}** · New message. / **${name}** · Nouveau message. | Standalone sentence under the name. Fixes the empty name: " sent you a message" |
| `preview` (previews on) | ${name}: ${text} / ${name}⎵: ${text} | **${name}** · ${text} | The name is in the title; `previewSeparator` is removed |
| `someone` (empty name) | used only in the body | **Someone** / **Quelqu'un** as the title (server, app, Stream template) | Bug fix: never an empty title |

## 2. Stream message push (`scripts/stream-push.ts`, `_shared/stream.ts`)

| Location | Current text (EN / FR) | New text (EN / FR) | Rationale |
|---|---|---|---|
| APNs template, title | drafft | `{{ sender.name }}`, else `drafft_push.someone`, else "Someone" | Push = name. No empty title |
| Template body, previews on | `{{ sender.name }}{{ separator }}{{ message.text }}` | `{{ message.text }}` (else the sentence below) | The name is in the title |
| Template body, previews off / fallback | `{{ sender.name }} {{ drafft_push.message }}` / EN fallback "{{ sender.name }} sent you a message" (served to everyone) | `drafft_push.message` (New message. / Nouveau message.), else "New message." | A leading space and no subject when the name was empty. EN is now only the fallback for a Stream user that hasn't been written yet |
| `drafft_push` on the Stream user | `{ message, separator, previews }` | `{ message, someone, previews }` | The localized fallback title |

## 3. Session cards in the chat (`db-events/handlers.ts`, now `texts.sessionCard`)

| Location | Current text (EN) | New text (EN) | Rationale |
|---|---|---|---|
| proposed | Proposed a session | Proposed a session | Unchanged (already the right verb) |
| accepted | Accepted the session | Confirmed the session | Lexicon: "Session confirmed", same as the push |
| declined | Declined the session | Declined the session invite | Lexicon: what's declined is the invite |
| cancelled / auto-cancelled | Cancelled the session | Cancelled the session | Unchanged, now centralised (covered by the test) |

These stay in English on purpose, and it's documented. They're one Stream message for two people who may not share a language. The app never shows them: it draws the card from `drafft.status`, and `Message.previewText` builds its own preview ("Session: Padel, Tue 14"). Only sophros and Stream search read them. See flag F3.

## 4. Auth emails (`emails.ts`)

| Location | Current text (EN / FR) | New text (EN / FR) | Rationale |
|---|---|---|---|
| all `.subject` | {code} is your code / {code} est ton code | unchanged | Needed for iOS autofill (the code comes first). ≤ 45 characters |
| confirm.title | Welcome to drafft / Bienvenue sur drafft | Confirm your email. / Confirme ton adresse e-mail. | One idea: the action. Headline with a full stop |
| confirm.body | To confirm your email in drafft, enter this code: / Pour confirmer ton e-mail dans drafft, saisis ce code⎵: | To finish signing up, enter this code: / Pour finir ton inscription, saisis ce code⎵: | Gives the why, still ends on "code:" (autofill) |
| all `.note` | Valid for 1 hour. / Valable 1 heure. | It works for 1 hour. / Il est valable 1⎵heure. | Less robotic, close to the app ("The code works for 1 hour."), without repeating the word "code" |
| confirm.ignore | If you didn't sign up for drafft, you can ignore this email. / Si tu n'as pas créé de compte drafft, tu peux ignorer cet e-mail. | Didn't sign up for drafft? You can ignore this email. / Tu n'as pas créé de compte drafft⎵? Tu peux ignorer cet e-mail. | More direct, reads faster |
| reset.title / body | Reset your password / To choose a new drafft password, enter this code: (FR Réinitialise ton mot de passe / Pour choisir un nouveau mot de passe drafft, saisis ce code⎵:) | Reset your password. / To choose a new password, enter this code: (FR Réinitialise ton mot de passe. / Pour choisir un nouveau mot de passe, saisis ce code⎵:) | Full stop on the headline. "drafft" was redundant (sender plus wordmark) |
| reset.ignore | If you didn't ask for this, you can ignore this email: your password stays the same. / Si tu n'as rien demandé, ignore cet e-mail⎵: ton mot de passe ne change pas. | Didn't ask for this? Ignore this email: your password stays the same. / Tu n'as rien demandé⎵? Ignore cet e-mail⎵: ton mot de passe ne change pas. | Shorter, the reassurance stays |
| newEmail.title / body | Confirm your new email / To switch your drafft account to {email}, enter this code: (FR Confirme ta nouvelle adresse / Pour passer ton compte drafft sur {email}, saisis ce code⎵:) | Confirm your new email. / To move your drafft account to {email}, enter this code: (FR Confirme ta nouvelle adresse e-mail. / unchanged body) | Full stop. Placeholder unchanged |
| reauth.title / body | Confirm it's you / To change your drafft password, enter this code: | Confirm it's you. / To change your password, enter this code: (FR Confirme que c'est toi. / Pour changer ton mot de passe, saisis ce code⎵:) | Same |
| newEmail/reauth.ignore | If you didn't ask for this, you can ignore this email. / Si tu n'as rien demandé, tu peux ignorer cet e-mail. | Didn't ask for this? You can ignore this email. / Tu n'as rien demandé⎵? Tu peux ignorer cet e-mail. | Same form as the others |

## 5. Account notices and support (`notices.ts`)

| Location | Current text (EN / FR) | New text (EN / FR) | Rationale |
|---|---|---|---|
| accountRestored.subject / title | Your drafft account is open again · You're all set / Ton compte drafft est de nouveau ouvert · Tout est en ordre | Your account check is done · Your account check is done. / La vérification de ton compte est terminée · (same, with a full stop) | Answers the app's hold screen ("We're checking your account."). The title repeats the subject. "You're all set" was a cliché |
| accountRestored.body | We've finished checking your account: everything is in order. Your profile is visible again, and your matches and chats are right where you left them. / Nous avons terminé la vérification… tout est en ordre… t'attendent là où tu les as laissés. | All good: your profile is visible again, and your matches and chats are still there. / Tout est bon⎵: ton profil est de nouveau visible, et tes matchs et discussions sont toujours là. | « Nous » becomes « on »/neutral. No longer administrative. Doesn't repeat "where you left off" from the note |
| accountRestored.note | Open drafft to pick up where you left off. / Ouvre drafft pour reprendre où tu en étais. | unchanged | Already a single CTA |
| accountReopened.subject / title | Your drafft account has been reopened · Welcome back / Ton compte drafft a été rouvert · Content de te revoir | Your drafft account is reopened · Your account is reopened. / Ton compte drafft est rouvert · Ton compte est rouvert. | Masculine default removed (5.4). The title repeats the subject |
| accountReopened.body | We've looked at your account again and reopened it. … / Nous avons réexaminé ton compte et l'avons rouvert. … | We took another look at your account. Your profile is visible again, and you can use drafft as before. / On a réexaminé ton compte. Ton profil est de nouveau visible et tu peux utiliser drafft comme avant. | « on » |
| accountReopened.note | Thanks for your patience. / Merci pour ta patience. | Open drafft to pick up where you left off. / Ouvre drafft pour reprendre où tu en étais. | Cliché replaced by a single next step |
| photoApproved (subject / title / body / note) | Your photo has been approved · Your photo is live · You asked for a second look… Our team checked it: it's approved and now on your profile. · Thanks for taking the time to ask. / Ta photo a été acceptée · Ta photo est en ligne · …Notre équipe l'a vérifiée⎵: … · Merci d'avoir pris le temps de nous le demander. | Your photo is approved · Your photo is approved. · We took a second look, as you asked: it's now on your profile. · Open drafft to see your profile. / Ta photo est validée · Ta photo est validée. · On l'a revue, comme tu l'as demandé⎵: elle est maintenant sur ton profil. · Ouvre drafft pour voir ton profil. | One idea. « on », no « notre équipe ». Same verb as the push (« validée »). Note = CTA |
| photoRefused (subject / title / body) | About the photo you asked us to check · We looked at your photo again · …it doesn't meet our photo guidelines, so it stays off your profile. / À propos de la photo que tu nous as demandé de revoir (55 characters) · Nous avons revu ta photo · …Notre équipe… nos règles… | Your photo can't go on your profile · (same, with a full stop) · We took a second look, as you asked: it doesn't fit the drafft photo guidelines, so it stays off your profile. / Ta photo ne peut pas aller sur ton profil · (same) · On l'a revue, comme tu l'as demandé⎵: elle ne respecte pas les règles photo de drafft, elle reste donc hors de ton profil. | The FR subject was > 45 characters and vague. It now states the outcome, plain and firm. « on », « les règles de drafft » |
| photoRefused.note | You can add another photo anytime in drafft. / Tu peux ajouter une autre photo quand tu veux dans drafft. | unchanged | Already the right way out |
| supportReceived (subject / title / body) | We got your message · Message received · Thanks for writing to us. We'll reply… Your reference: / Nous avons bien reçu ton message · Message reçu · Merci de nous avoir écrit. Nous te répondrons… Ta référence⎵: | We got your message · We got your message. · We'll reply to this address, usually within 2 working days. Your reference: / On a bien reçu ton message · On a bien reçu ton message. · On te répond à cette adresse, en général sous 2⎵jours ouvrés. Ta référence⎵: | « on ». The title repeats the subject. The redundant thanks is dropped |
| supportReceived.note | Keep this reference if you write to us again. / Garde cette référence si tu nous écris de nouveau. | Mention it if you write to us again. / Indique-la si tu nous réécris. | Less administrative, says what to do with it |
| supportReply.title | From the drafft team / De la part de l'équipe drafft | A reply from the drafft team. / Une réponse de l'équipe drafft. | Says what it is. « l'équipe drafft » as the signature |
| supportReply.intro | Here's our reply about: {topic} / Voici notre réponse au sujet de : {topic} (plain space) | Topic: {topic} / Sujet⎵: {topic} | Missing NBSP fixed. « notre » removed. Short |
| supportReply.note | Just reply to this email to write back. Your reference: / Réponds simplement à cet email pour nous écrire. Ta référence : (plain space, « email ») | Reply to this email to write back. Your reference: / Réponds à cet e-mail pour nous écrire. Ta référence⎵: | NBSP fixed, « e-mail » as in the auth emails |
| supportReply, text version "Your message:" | `${yours}:` (FR without NBSP) | FR `Ton message⎵:` | Missing NBSP (code) |
| supportReply, HTML note | `small(escape(note))`, escaped twice | `small(note)` | "&" would have shown as "&amp;" |

## 6. SMS (`sms.ts`)

| Location | Current text (EN / FR) | New text (EN / FR) | Rationale |
|---|---|---|---|
| verification | Your drafft code is ${c} / Ton code de vérification est ${c} | Your drafft code is ${c} / Ton code drafft est ${c} | The brand is now in all 7 languages (ES "Tu código de drafft es", DE "Dein drafft-Code ist", IT "Il tuo codice drafft è", PT "O teu código drafft é", NL "Je drafft-code is"). The sender is a number in countries without alphanumeric IDs. The code stays last |

## 7. App Store products (`scripts/app-store-products.ts`, en-US)

| Location | Current text | New text | Rationale |
|---|---|---|---|
| boost.1/5/10 names | 1 Boost · 5 Boosts · 10 Boosts | 1 boost · 5 boosts · 10 boosts | Lexicon: lowercase, including store names |
| boost description | 30 minutes at the top of decks nearby | 30 minutes up front for people near you | "decks" jargon removed (39 characters ≤ 45) |
| superlike.3/15/30 names | 3 Super Likes … | 3 super likes · 15 super likes · 30 super likes | Lexicon |
| tempo, descriptions | unchanged | unchanged | Already compliant |

## 8. Test and verification

- New `supabase/functions/_tests/wording_test.ts`. It imports `texts`, `emails`, `notices` and `sms`, walks every exported object and calls every copy function in all 7 languages (rendered emails included), which gives more than 500 strings. It fails if:
  - a pattern from the `wording-forbidden` block of `../../WORDING.md` matches (read at runtime, case-insensitive);
  - a French string is missing a NBSP before `: ; ! ? »` or after `«`;
  - any string has "!" or a capitalised "Drafft";
  - an email subject is over 45 characters.

  A guard test fails if a new exported function is neither sampled nor declared as non-copy. I also checked that the patterns do catch "It's a match…", "plan", "geplant", "Oops" and others.
- **Verify command change (AGENTS.md and `.github/workflows/backend.yml`, step "Unit and Edge Function auth tests").** The test reads the WORDING.md file at the repo root, outside `supabase/functions`:
  - `deno test --allow-env --allow-read=.` → `deno test --allow-env --allow-read=.,../../WORDING.md`
  - With the old command, the test fails with `NotCapable: Requires read access to ".../WORDING.md"`.
- Result: `deno fmt --check`, `deno lint`, `deno check ./*/index.ts`, `deno test` (99 passed, 0 failed) and `deno check scripts/*.ts` all pass. `supabase test db` and `db advisors` weren't run: they need a local database, and no SQL was touched.
- App: `design_lint.py` is clean. `i18n_lint.py | grep NotificationText` returns nothing (the 2 former "It's a match" errors are gone; 0 errors overall). `NotificationText.swift` compiles with `swiftc` against an `AppLanguage` stub. No Xcode build.

## Flags not fixed

- **F1. Deployment order, Stream push.** First run `deno run … scripts/stream-push.ts apply` (the new template) on each environment. Then deploy the functions (`db-events`, `stream-webhook`, `auth-email`, `auth-sms`, all of which import these files). Then rewrite every Stream user, so each one gets `drafft_push.someone` and the new `message` (otherwise the old "sent you a message" stays on the user). The template falls back to English, and in between it shows "Maya · sent you a message", which is readable. This is noted in the header of `stream-push.ts`. Nothing was run (no remote access).
- **F2. `Notifications.swift` touched** (one line plus its doc comment) outside my two files: that's where the title of local notifications is set. Check it doesn't conflict with another agent.
- **F3. Session chat cards stay English-only.** Localizing them would need one message per recipient (it's one Stream message for two people) or a template on Stream's side. The app doesn't show them. Only sophros and Stream search do.
- **F4. "Séance Running", "Laufen-Session", "Run club session".** `sessionName` must match the app's key "%@ session" (`Session.displayTitle`). Fixing it (FR « séance de running » with elision and lowercase, DE compounds) has to happen on both sides at the same time, together with the app's catalog.
- **F5. Useful time in session pushes.** "Proposed a session: Padel session" doesn't give the time. Adding the times (e.g. "Léa proposed 2 times. Pick one.", the WORDING example) needs the recipient's time zone (it lives in `private.devices`, and the reminders read it through the SQL queue): that's a data change, not a copy change. When untitled, the proposal body repeats "session" ("Proposed a session: Padel session").
- **F6. Emails have no preheader.** Inbox previews show "drafft {title} {body}". Adding one is a small change to `layout()`, not made here.
- **F7. The support reply subject** `Re: {topic} [{reference}]` isn't localized (mail convention, left as is; excluded from the FR check).
- **F8. IAP en-US only, create-only script.** The new names and descriptions only apply to products that don't exist yet. Live products and the 6 other locales have to be edited in App Store Connect. Also align `StoreKit/Drafft.storekit` (app side) with "1 boost", "3 super likes" and "30 minutes up front for people near you".
- **F9. Server error sentences** (`phone_code.ts:81` "Phone sign-in isn't available.", `private.fail` messages): developer strings the app doesn't show (it shows its own mapping). Not touched.
- **F10. Unused `config.toml` templates** ("Your code is {{ .Code }}"): the hooks replace them. Not touched.
- **F11. JS vs Python regexes.** `\b` and `\w` are ASCII in JS and Unicode in Python. The backend test can be very slightly stricter than `i18n_lint.py` next to an accented letter. No false positives today.
- **F12. WORDING.md.** The 4 decisions above (push structure, FR « on », email title = subject, fallback « Quelqu'un ») should go into section 11 of `drafft/WORDING.md`, then be synced. I didn't touch the synced copy.
