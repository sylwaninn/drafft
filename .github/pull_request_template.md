<!--
Title: type(scope): lowercase description, no final period. It becomes the squash commit on staging.
  types: feat, fix, docs, style, refactor, test, chore. `type!:` for a breaking change.
Base: staging. Never main (main only moves through the release workflow).
No AI attribution line in the description or in any commit (CI refuses it, scripts/ci/pr_check.sh).
Delete these comments and any section that doesn't apply.
-->

## Summary

<!-- What changes for the person using drafft, in two or three sentences. Then why. -->

## Changes

<!-- The main changes, one line each, with the types or files that carry them. -->

-

## Testing

<!-- What you ran and what you saw. Say what you did not run. -->

- [ ] `xcodegen generate` and the compile-only build (`Drafft` scheme, generic iOS Simulator)
- [ ] `swiftlint lint --strict --baseline .swiftlint-baseline.json`
- [ ] `python3 scripts/ci/design_lint.py` and `python3 scripts/ci/i18n_lint.py`
- [ ] Unit tests (`DrafftTests`, Drafft Local scheme)
- [ ] Run on the local backend (`Drafft Local`), steps:
  1.

## Screenshots

<!-- UI changes: before / after, light and dark, the longest language (FR, DE or NL) when a label moved. -->

## Notes

- **Telemetry:** <!-- events, screens, errors and alerts added (docs/telemetry.md), or "none, because ..." -->
- **Wording:** <!-- strings added or changed in the 7 languages after WORDING.md section 10, or "no user-facing text" -->
- **Privacy:** <!-- new data leaving the phone, a new permission, PrivacyInfo.xcprivacy, or "none" -->
- **Companion pull requests:** <!-- drafft-android, drafft-backend, drafft-web, or "none" -->
- **Breaking change:** <!-- what a client or the backend must do, or "none" -->
