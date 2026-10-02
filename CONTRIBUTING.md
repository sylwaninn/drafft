# Contributing

How changes reach drafft-ios. Coding agents follow [AGENTS.md](AGENTS.md), which holds the same rules.
The other drafft repositories work the same way; their AGENTS.md says where they differ.

## Branches

| Branch | Role | Moves through |
|---|---|---|
| `staging` | default branch, integration | squash-merged pull requests only |
| `main` | production | the release workflow only |
| `feat/*`, `fix/*`, `chore/*`, `docs/*`, `refactor/*` | work | your pushes |

Both `staging` and `main` are protected, and the `pre-push` hook refuses direct pushes to them.

## Commits

One line, [Conventional Commits](https://www.conventionalcommits.org/), lowercase, no final period, no body,
no trailers:

```text
feat(mobile): show likes as a banner over an equal blurred grid
fix(mobile): keep button labels on one line in every language
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore` (`type!:` for a breaking change).
The `commit-msg` hook enforces it.

## Signed commits

Sign every commit with an SSH key registered on GitHub as a signing key, so each one shows as
**Verified**:

```sh
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
git config --global tag.gpgsign true
```

Squash merges made on GitHub are signed by GitHub and keep you as the author.

## Pull requests

1. Branch from `staging`, commit, push, open a pull request **into `staging`**.
2. The title follows the commit format: it becomes the squash commit.
3. Fill in the [template](.github/pull_request_template.md): summary, changes, testing, and the notes on
   telemetry, wording, privacy and companion pull requests.
4. Run the checks below before asking for a merge. Squash and merge, then delete the branch.

## Verify locally

```sh
xcodegen generate && xcodebuild -project Drafft.xcodeproj -scheme Drafft \
  -destination 'generic/platform=iOS Simulator' build
swiftlint lint --strict --baseline .swiftlint-baseline.json
python3 scripts/ci/design_lint.py && python3 scripts/ci/i18n_lint.py
```

Unit tests run from Xcode (`⌘U`) on the Drafft Local scheme.

## Quality gates

Every pull request runs two workflows on Linux runners. Building, testing and archiving belong to
Xcode, which has the toolchain and the signing.

| Workflow | Job | Checks |
|---|---|---|
| [`app.yml`](.github/workflows/app.yml) | swift | SwiftLint, strict, new violations only (debt in `.swiftlint-baseline.json`) |
| | design | DESIGN.md rules: palette colours only, no gradient but photo scrims, a surface on every sheet, lowercase brand |
| | i18n | 7 languages complete, matching placeholders, catalog in sync with the code, WORDING.md's forbidden patterns |
| | hygiene | gitleaks over the whole history, actionlint, media files under 1 MB, public keys only, telemetry in the EU |
| [`pr.yml`](.github/workflows/pr.yml) | pr | base is not `main`, title format, description filled in, commit authors, no attribution trailer, signatures |

A deliberate exception to a design rule carries its reason in the code:
`// design-lint: allow <rule> - <why>`.
