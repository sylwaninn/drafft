#!/usr/bin/env bash
# Copies the shared docs from drafft-ios (their one source) into the other repositories' checkouts,
# found next to this one: WORDING.md into drafft-backend, drafft-web and drafft-android, DESIGN.md into
# drafft-android. Edit them here only, run this, then commit each repository (one pull request each).
# Usage: scripts/sync-shared.sh [--check]   (--check: exit 1 if a copy differs, change nothing)
# DRAFFT_REPOS=<folder> looks for the checkouts in that folder instead.
set -euo pipefail

source_repo="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "${DRAFFT_REPOS:-$source_repo/..}" && pwd)"
check=false
[ "${1:-}" = "--check" ] && check=true
status=0

header() { echo "<!-- Shared copy of drafft-ios/$1, kept identical in every repository that has it. Changing it? Ask whether the other copies follow (AGENTS.md, Shared docs). -->"; }

# Renders $source_repo/$1 with the header, after the YAML front matter when the file has one.
render() {
  awk -v h="$(header "$1")" '
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm && $0 == "---" { fm = 0; print; print ""; print h; next }
    NR == 1 { print h; print "" }
    { print }
  ' "$source_repo/$1"
}

sync() {
  local file=$1 repo=$2 target="$root/$2/$1"
  if $check; then
    if ! render "$file" | cmp -s - "$target"; then echo "out of date: $repo/$file"; status=1; fi
  else
    render "$file" > "$target"
    echo "synced $repo/$file"
  fi
}

for repo in drafft-backend drafft-web drafft-android; do
  if [ ! -e "$root/$repo/.git" ]; then
    echo "skip $repo: no checkout at $root/$repo" >&2
    continue
  fi
  sync WORDING.md "$repo"
  if [ "$repo" = drafft-android ]; then sync DESIGN.md "$repo"; fi
done
exit $status
