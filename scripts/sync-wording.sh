#!/usr/bin/env bash
# Copies WORDING.md, the one source for user-facing copy, into the sibling drafft-backend and
# drafft-web checkouts. Edit WORDING.md here only, run this, then commit each repository.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
header='<!-- Synced copy of drafft/WORDING.md. Do not edit here: edit it in drafft, then run drafft/scripts/sync-wording.sh. -->'

for repo in drafft-backend drafft-web; do
  target="$root/../$repo"
  if [ ! -d "$target/.git" ] && [ ! -f "$target/.git" ]; then
    echo "skip $repo: no checkout at $target" >&2
    continue
  fi
  { echo "$header"; echo; cat "$root/WORDING.md"; } > "$target/WORDING.md"
  echo "synced $repo/WORDING.md"
done
