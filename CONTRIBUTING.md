# Contributing

How changes reach drafft-ios: branches, commits, pull requests, local checks and CI. This file is the
reference for them; [AGENTS.md](AGENTS.md) adds what coding agents must also follow.

## Branches

| Branch | Role | Moves through |
|---|---|---|
| `staging` | default branch, integration | squash-merged pull requests only |
| `main` | production | the release workflow only |
| `feat/*`, `fix/*`, `chore/*`, `docs/*`, `hotfix/*` + a short kebab-case name | work | your pushes |

Branch from a fresh `origin/staging`. Both `staging` and `main` are protected, and the `pre-push` hook refuses
direct pushes to them.

## Commits

One line, [Conventional Commits](https://www.conventionalcommits.org/), no body, no trailers:
`type(scope): description`.

- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`.
- Scope, required: `mobile` (`ci` for workflows).
- Description: lowercase, imperative, starts with a verb, no final period.
- One logical change per commit, each passing the checks below.

```text
feat(mobile): show likes as a banner over an equal blurred grid
fix(mobile): keep button labels on one line in every language
```

The `commit-msg` hook checks the format (one line, lowercase, no final period, no `Co-Authored-By`); the pull
request check also requires the scope and refuses AI attribution lines.

## Signed commits

Sign every commit with an SSH key registered on GitHub as a signing key, so each one shows as **Verified**
(CI warns about unsigned commits for now):

```sh
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
git config --global tag.gpgsign true
```

Squash merges made on GitHub are signed by GitHub and keep you as the author.

## Pull requests

1. Commit, push, open a pull request **into `staging`**.
2. The title follows the commit format, scope required, 70 characters at most: it becomes the squash commit.
   A breaking change is marked in the title only, `type(scope)!:` (it gives a major version; any `feat` a
   minor, anything else a patch).
3. Fill in every section of the [template](.github/pull_request_template.md).
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

Every pull request runs two workflows on Linux runners. Building, testing and archiving happen in Xcode, which
has the toolchain and the signing.

| Workflow | Job | Checks |
|---|---|---|
| [`app.yml`](.github/workflows/app.yml) | swift | SwiftLint, strict, new violations only (debt in `.swiftlint-baseline.json`) |
| | design | DESIGN.md rules (`scripts/ci/design_lint.py`): no `·` separator, no gradient but photo scrims and blur masks, no `…` on copy, lowercase brand, palette colours only, no console output, no secret, a surface on every sheet |
| | i18n | 7 languages complete, matching placeholders, catalog in sync with the code, WORDING.md's forbidden patterns (also in `Services/NotificationText.swift`) |
| | hygiene | gitleaks over the whole history, actionlint, media files under 1 MB, public keys only, telemetry in the EU |
| [`pr.yml`](.github/workflows/pr.yml) | pr | base is not `main`, title format, description filled in, commit authors, no attribution trailer; unsigned commits are a warning |

A deliberate exception to a design rule carries its reason in the code:
`// design-lint: allow <rule> - <why>`.
