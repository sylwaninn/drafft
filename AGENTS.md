# Instructions for AI agents

drafft iOS app (SwiftUI, XcodeGen). Product and design context: [PRODUCT.md](PRODUCT.md),
[DESIGN.md](DESIGN.md). Backend: the `drafft-backend` repository.

## User-facing text: WORDING.md first (priority rule)

Before writing or changing any text people see (UI strings in any of the 7 languages, CTAs, errors,
empty states, push, email, paywall, store listings, website, screenshots, marketing), read and apply
[WORDING.md](WORDING.md), then run its review checklist (section 10). The `wording` skill (`.claude/skills/wording/`) walks through it. Never write "plan" in any sense or language, and never
present a match as turning into something. New editorial decisions go into WORDING.md only (here, the
reference copy; see "Shared docs" for the other repositories' copies).

## Telemetry (Sentry and PostHog): part of every change

[docs/telemetry.md](docs/telemetry.md) is the reference (events, screens, errors, alerts); the code is
`Drafft/Services/Telemetry/`, the same events and rules as the Android app.

**Every feature, change or task finishes with a telemetry pass. The pull request's "Notes" says what was
done, or "Telemetry: none, because ..." (a refactor, a copy change).** The checklist:

1. **Events.** What the person did and whether it worked: a factory in `AnalyticsEvent` (`object_action`, snake_case,
   past tense, typed properties: numbers, booleans, codes, never free text), fired where the model knows
   the outcome (after success; a `*_failed` event with a `reason` code on failure). Same name and
   properties on Android, in the same change or its twin pull request. Never rename an event or a
   property: add a new one.
2. **Screens.** A new pushed screen, sheet or cover gets `.trackScreen(.x)` (a paywall `.trackPaywall(kind)`), with its `Screen` case.
3. **Errors.** A `catch` that swallows or rethrows something unexpected calls
   `Telemetry.unexpected(error, area, action)`: only what needs a fix alerts (not offline, not a refusal
   the screen explains). Log with `AppLog`, never `os.Logger` directly.
4. **Alerts.** A flow that costs money, accounts or safety (sign-up and sign-in, purchases, deletion,
   moderation, push, chat send) gets its alert, not only its event: a Sentry alert rule filtered on
   `environment:production` (and the `area` tag), and a PostHog alert or insight on the failure event.
   Write it in the "Alerts" part of `docs/telemetry.md`; create it through the PostHog MCP / Sentry when
   asked.
5. **Conventions, always.** One PostHog project for the two apps and the website, one Sentry project per
   app, each shared by production and staging: every insight, funnel, alert and experiment filters `app_environment = production`
   (PostHog; the project's test-account filter already does) and `environment:production` (Sentry).
   Never switch the privacy rules off to get a number: consent, `PrivacyGuard`, no screenshots or replay
   (docs/telemetry.md).
6. **Docs and tests.** The event goes in the doc's table and in the `TelemetryTests` catalog test.

Never put what people typed, their sensitive answers (gender, who they want to meet, lifestyle), their
location or another person's id in an event, a tag or a log line. `PrivacyGuard` drops it anyway, and unit
tests fail on it.

## Working with the user

- **Rules live in this repository, never in an agent's memory.** A rule the user gives (design, copy,
  product, way of working) goes into the document it belongs to, in the same change: DESIGN.md,
  PRODUCT.md, this file, or WORDING.md (in drafft-ios, its source). Never save it to Claude Code's auto
  memory: a cloud session, another machine or another agent would never see it.
- **Who drafft is for stays in PRODUCT.md.** The audience (age above all, city, how often people train) is
  never written in a README or any other doc. A README never details what a session proposal holds.
- **Two standalone apps.** Never describe drafft for Android as a port, a copy, a mirror or a translation of
  this app (or the reverse), in code, comments, docs, commits or pull requests.
- **Industry-grade solutions.** Every fix or feature takes the robust, secure, scalable solution the
  industry already uses (proven libraries and patterns: idempotency keys, retries with backoff,
  dead-letter queues and redrive, circuit breakers, stale-while-revalidate), never a quick patch.
  Challenge it before presenting it: name the pattern, its failure modes and how they are covered.
- **Design calls are yours.** On design and build tasks, decide the structure, the call to action and the
  wording (within WORDING.md) and say what you chose in the summary, instead of a round of questions.
  Lean modern: rich motion and micro-interactions.
- **Never check screens yourself**: no screenshots, no visual review by a subagent.
  Build, install and launch the app on the Simulator (`Drafft Local`), then hand over.
  The user checks the result themselves.
- **On the user's iPhone, launch only on their go.** Install the build (`-configuration Local`, which is
  optimised: Debug builds stall for up to a second on device and get reported as bugs), then stop.
  Launch or relaunch only once the user says "ok" or "prêt": they set the phone up first (Network Link
  Conditioner, for instance). On the go, reset what the run needs (swipes, `-deckPhotoReset`), then launch.
- **Always live** (PRODUCT.md principle 7): any server state the person can see listens to the account's
  Realtime channel and is read again on foreground and reconnect. Never a relaunch or a pull to refresh.
- **Reviews run in depth, never trimmed.** A review (`/pr-review-toolkit:review-pr`, a pull request
  audit) uses every applicable specialist agent on each pull request (code-reviewer,
  silent-failure-hunter, pr-test-analyzer, comment-analyzer, type-design-analyzer, then code-simplifier).
  Batch by repository if needed; never drop an aspect to save agents.
- **Don't wait for CI or deploys.** Start the run, look at its status once if useful, report and move on.
  Never block on `gh run watch`.

## Repository rules

Everything an agent needs is in this repository: this file, the docs it links, and `.claude/` (settings,
git guard, skills). Claude Code loads the same files on this machine and on the web.

### Branches and commits

- Never commit on `main` and `staging`. Branch from a fresh `origin/staging` (`git fetch origin` first), named
  `feat/`, `fix/`, `chore/`, `docs/` or `hotfix/` + a short kebab-case name.
- Commit messages: `type(scope): description`, one line, no body, no trailers. Types: feat, fix, docs,
  style, refactor, test, chore. Scope (required): `mobile` (`ci` for workflows). The description is lowercase,
  imperative, starts with a verb and has no final period. Example: `feat(mobile): add voice message replies`.
- Commits are authored by the user only: never a `Co-Authored-By` or any AI attribution line
  (`.claude/settings.json` turns Claude Code's off; the `commit-msg` hook and CI refuse them).
- One logical change per commit; every commit passes verify. Never `--no-verify`.
- Enforcement: the git hooks in `.agents/git-hooks/` (`git config core.hooksPath .agents/git-hooks`,
  which `.claude/settings.json` runs at the start of every session) and, for Claude Code,
  `.claude/hooks/guard-git.py` (commits and pushes to `main` and `staging`, deleting them, `--no-verify`). If a hook
  refuses, change the approach; never work around it.

### Pull requests and releases

- Open them with the `create-pr` skill (`.claude/skills/create-pr/`), into `staging`. Title in
  conventional commit format, English, 70 characters at most (it becomes the squash commit and feeds
  the release version: `type(scope)!:` major, any `feat` minor, else patch). Every section of the body filled,
  no AI attribution. Squash-merge.
- Never merge a pull request whose checks are red or still running, never with admin rights.
- A merge into `staging` runs CI only. A release (Actions > release, started by hand on GitHub) fast-forwards `main` to `staging`, tags `vX.Y.Z` and publishes a GitHub release; store builds are made by hand from that tag.
- Agents never start a release or a deploy unless the user asks for it in the current request, and
  never tag by hand.

### Secrets

Never open, print, copy, search or summarize `.env*` files (`.env.example` is safe), `.dev.vars`
(`.dev.vars.example` is safe), keys, `google-services.json` or anything in `~/Secrets/`, by any means.
Run the CLI that consumes them without showing them, and only when the user asks: it writes to a remote
project. Never write, regenerate or overwrite a user's `.env.local`. `.claude/settings.json` denies the
reads.

### Environments

Apps an agent installs or launches always target the local Supabase. Never build, install, deploy or run
mutations against staging or production unless the user asks for that environment in the current
request. Compile-only checks are the exception.

### Work that spans repositories

A product feature usually runs backend, then the two apps (then the website for legal or marketing
copy): one session and one pull request per repository, backend first since the apps call its RPCs and
functions. Both apps ship it with the same names, behaviour and strings. The first
pull request states the contract (RPCs, payloads, event names) and the next ones link it. Another
repository is read on GitHub (`gh repo clone sylwaninn/<repo>` into a temporary folder), never edited
from here, except the shared docs below when the user agrees.

### Shared docs

`WORDING.md` (in drafft-ios, drafft-android, drafft-backend and drafft-web) and `DESIGN.md` (in drafft-ios
and drafft-android) are one document kept identical in each repository; drafft-ios holds the reference.
**After changing either one here, ask the user whether the change goes to the other repositories' copies.**
If yes, make the identical change in each, one pull request per repository (`gh repo clone
sylwaninn/<repo>` into a temporary folder, a branch from its base, the `create-pr` skill), and link the
pull requests to each other. Locally, drafft-ios's `scripts/sync-shared.sh` writes the copies from
drafft-ios, and `--check` lists those that differ.

### This repository

`staging` (the default branch) takes every pull request; `main` is production and only moves through
the release workflow (Actions > release: staging's new commits onto `main`, a `vX.Y.Z` tag and a GitHub
release, see `scripts/ci/release.sh`). Store builds are made by hand, from the release tag. "Verify" in these rules
means, in this repository (the same as CONTRIBUTING.md, "Verify locally"):

```sh
xcodegen generate && xcodebuild -project Drafft.xcodeproj -scheme Drafft -destination 'generic/platform=iOS Simulator' build
swiftlint lint --strict --baseline .swiftlint-baseline.json
python3 scripts/ci/design_lint.py && python3 scripts/ci/i18n_lint.py
```

CI runs the lints, gitleaks and actionlint on every pull request, and checks the pull request itself: the
full list is in CONTRIBUTING.md, "Quality gates". SwiftLint fails on new violations only (existing debt is in
`.swiftlint-baseline.json`). A deliberate exception to a design rule carries its reason:
`// design-lint: allow <rule> - <why>`.

Environments: scheme **Drafft** (production backend) and **Drafft Staging** ("drafft β", staging
backend), from `Config/*.xcconfig`. **Drafft Local** ("drafft local") runs on the local Supabase of
drafft-backend with its staging services: `supabase start` there, then `scripts/local-backend.sh` (add
`--device` for an iPhone on the same Wi-Fi) writes the machine's URL and key to the gitignored
`Local.private.xcconfig`. Never put a secret in the app: only public keys go there.

**Run the app on the local backend, always.** Every build an agent installs or launches (Simulator
or iPhone) is `-scheme "Drafft Local" -configuration Local`. NEVER build, install or launch against
production or staging (`Drafft`, `Drafft Staging`, `-configuration Release`, `Debug` or `Staging`)
unless the user explicitly asks for that environment in the current request. All schemes share the
bundle id `so.drafft.app`, so any other build silently replaces the local app and sends real actions
(sign-ups, likes, messages) to that backend. Before installing, check the built app's
`Info.plist`: `SupabaseURL` must be the local machine's address. Compile-only checks (the verify
command above, no install, no launch) are the one exception.
