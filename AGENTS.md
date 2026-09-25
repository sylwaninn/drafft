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
```

Environments: scheme **Drafft** (production backend) and **Drafft Staging** ("drafft β", staging
backend), from `Config/*.xcconfig`. Never put a secret in the app: only public keys go there.

@.agents/rules/commits.md
@.agents/rules/github.md
