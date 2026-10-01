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
request. SwiftLint fails on new violations only (existing debt is in `.swiftlint-baseline.json`). The
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
