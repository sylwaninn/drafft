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
