#!/usr/bin/env bash
# Copies WORDING.md, the one source for user-facing copy, into the sibling drafft-backend,
# drafft-web and drafft-android checkouts, and DESIGN.md into drafft-android (the Android port follows
# the same design rules). Edit them here only, run this, then commit each repository.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
header() { echo "<!-- Synced copy of drafft/$1. Do not edit here: edit it in drafft, then run drafft/scripts/sync-wording.sh. -->"; }

# Writes $root/$1 into $2/$1 with the header, after the YAML front matter when the file has one.
sync() {
  awk -v h="$(header "$1")" '
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm && $0 == "---" { fm = 0; print; print ""; print h; next }
    NR == 1 { print h; print "" }
    { print }
  ' "$root/$1" > "$2/$1"
  echo "synced $(basename "$2")/$1"
}

for repo in drafft-backend drafft-web drafft-android; do
  target="$root/../$repo"
  if [ ! -d "$target/.git" ] && [ ! -f "$target/.git" ]; then
    echo "skip $repo: no checkout at $target" >&2
    continue
  fi
  sync WORDING.md "$target"
  if [ "$repo" = drafft-android ]; then sync DESIGN.md "$target"; fi
done
