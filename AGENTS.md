# Instructions for AI agents

drafft iOS app (SwiftUI, XcodeGen). Product and design context: [PRODUCT.md](PRODUCT.md),
[DESIGN.md](DESIGN.md). Backend: the `drafft-backend` repository.

## User-facing text: WORDING.md first (priority rule)

Before writing or changing any text people see (UI strings in any of the 7 languages, CTAs, errors,
empty states, push, email, paywall, store listings, website, screenshots, marketing), read and apply
[WORDING.md](WORDING.md), then run its review checklist (section 10). The `wording` skill (workspace
`.claude/skills/wording/`) walks through it. Never write "plan" in any sense or language, and never
present a match as turning into something. New editorial decisions go into WORDING.md only (here, the
canonical copy; the workspace's `scripts/sync-docs.sh` copies it to drafft-backend, drafft-web and
drafft-android, with DESIGN.md).

## Telemetry (Sentry and PostHog): part of every change

[docs/telemetry.md](docs/telemetry.md) is the plan (events, screens, errors, alerts); the code is
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

## Workspace rules

This repository lives in the drafft workspace (the parent folder, see `../AGENTS.md`), which holds what
every repository shares: commit and GitHub rules (`../.claude/rules/`), the `create-pr` and `wording`
skills (`../.claude/skills/`), and the Claude Code settings and git guard (`../.claude/`). Start agents
there. In short: work on a branch, one-line commits `type(scope): description` without any
Co-Authored-By, a pull request into `staging`, verify first. The git hooks in `.agents/git-hooks/`
enforce it for agents and humans (`git config core.hooksPath .agents/git-hooks`, set by the
workspace's `scripts/bootstrap.sh`).

`staging` (the default branch) takes every pull request; `main` is production and only moves through
the release workflow (Actions > release: staging's new commits onto `main`, a `vX.Y.Z` tag and a GitHub
release, see `scripts/ci/release.sh`). Store builds are made by hand, from the release tag. "Verify" in these rules
(`pnpm verify`) means, in this repository:

```sh
xcodegen generate && xcodebuild -project Drafft.xcodeproj -scheme Drafft -destination 'generic/platform=iOS Simulator' build
swiftlint lint --strict --baseline .swiftlint-baseline.json
python3 scripts/ci/design_lint.py && python3 scripts/ci/i18n_lint.py
```

CI (`.github/workflows/app.yml`) runs the last two lines plus gitleaks and actionlint on every pull
request; `.github/workflows/pr.yml` checks the pull request itself (base never `main`, title format, a
filled-in description, allowed commit authors, no attribution trailer). SwiftLint fails on new violations only (existing debt is in `.swiftlint-baseline.json`). The
design lint encodes DESIGN.md's rules (no gradients but photo scrims, no '·', no '…' on copy, lowercase
brand, palette colours only, a surface on every sheet); a deliberate exception carries its reason:
`// design-lint: allow <rule> - <why>`. The i18n lint wants all 7 languages, matching placeholders,
a catalog in sync with the code, and none of the wording WORDING.md forbids (its `wording-forbidden`
block, also applied to `Services/NotificationText.swift`).

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
