# Instructions for AI agents

drafft iOS app (SwiftUI, XcodeGen). Product and design context: [PRODUCT.md](PRODUCT.md),
[DESIGN.md](DESIGN.md). Backend: the `drafft-backend` repository.

## Rules for every agent

Read these before committing or opening a pull request. They live in `.agents/` so any agent can use
them; Claude Code loads them through `CLAUDE.md`.

- Commits and branches: [.agents/rules/commits.md](.agents/rules/commits.md)
- GitHub (pull requests, comments): [.agents/rules/github.md](.agents/rules/github.md)
- Skills: `.agents/skills/` (`create-pr`, `technical-writer`)
- Git hooks that enforce them for everyone, agents and humans (`.agents/git-hooks/`): `commit-msg`
  (format, one line, no Co-Authored-By) and `pre-push` (no push to `main`). Enable once per clone:
  `git config core.hooksPath .agents/git-hooks`

`main` is protected by convention: work on a branch, open a pull request. "Verify" in these rules
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
`// design-lint: allow <rule> - <why>`. The i18n lint wants all 7 languages, matching placeholders and
a catalog in sync with the code.

Environments: scheme **Drafft** (production backend) and **Drafft Staging** ("drafft β", staging
backend), from `Config/*.xcconfig`. Never put a secret in the app: only public keys go there.

@.agents/rules/commits.md
@.agents/rules/github.md
