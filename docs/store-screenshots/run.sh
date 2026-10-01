#!/bin/zsh
# Store screenshots, end to end: see README.md in this folder.
#
#   docs/store-screenshots/run.sh              everything (about 20 minutes)
#   docs/store-screenshots/run.sh build        the capture build only
#   docs/store-screenshots/run.sh capture      the Simulator captures (needs build)
#   docs/store-screenshots/run.sh extract      cut the pieces (needs capture)
#   docs/store-screenshots/run.sh compose      the PNGs, from the cut pieces (seconds per language)
#   docs/store-screenshots/run.sh feature      the Google Play feature graphic (1024 x 500), from the same pieces
#
# STORE_WORK (default ~/Library/Caches/drafft-store-shots) keeps the build, captures and pieces;
# STORE_OUT (default ~/Projets/drafft/store-screenshots) receives the PNGs, one folder per store and device.
set -euo pipefail

HERE=${0:A:h}
REPO=${HERE:h:h}
WORK=${STORE_WORK:-$HOME/Library/Caches/drafft-store-shots}
OUT=${STORE_OUT:-$HOME/Projets/drafft/store-screenshots}
LANGS=(en fr es de it pt nl)
DEVICE="drafft store 6.9"
BUNDLE=so.drafft.app
mkdir -p "$WORK"

udid() {
  xcrun simctl list devices -j | python3 -c "
import json, sys
for rt, devs in json.load(sys.stdin)['devices'].items():
    for d in devs:
        if d['name'] == '$DEVICE' and d['isAvailable']: print(d['udid']); sys.exit()"
}

simulator() {
  local id=$(udid)
  if [[ -z $id ]]; then
    # The 6.9" iPhone (1320 x 2868, the App Store's required size), newest iOS runtime.
    local rt=$(xcrun simctl list runtimes -j | python3 -c "
import json, sys
rts = [r for r in json.load(sys.stdin)['runtimes'] if r['platform'] == 'iOS' and r['isAvailable']]
print(sorted(rts, key=lambda r: [int(x) for x in r['version'].split('.')])[-1]['identifier'])")
    id=$(xcrun simctl create "$DEVICE" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max "$rt")
  fi
  xcrun simctl boot "$id" 2>/dev/null || true
  xcrun simctl bootstatus "$id" -b >/dev/null
  xcrun simctl status_bar "$id" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 --operatorName ""
  echo "$id"
}

build() {
  local wt=$WORK/app id
  [[ -f $REPO/Local.private.xcconfig ]] || { echo "Local.private.xcconfig missing: run scripts/local-backend.sh first"; exit 1; }
  git -C "$REPO" worktree remove --force "$wt" 2>/dev/null || true
  git -C "$REPO" worktree add --detach "$wt" HEAD >/dev/null
  cp "$REPO/Local.private.xcconfig" "$wt/"
  git -C "$wt" apply "$HERE/store-shots.patch"
  id=$(simulator)
  (cd "$wt" && xcodegen generate --quiet && xcodebuild -quiet -project Drafft.xcodeproj -scheme "Drafft Local" -configuration Local \
    -destination "platform=iOS Simulator,id=$id" -derivedDataPath "$WORK/dd" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) STORE_SHOTS' build)
  local app=$WORK/dd/Build/Products/Local-iphonesimulator/Drafft.app
  # Always the local configuration (AGENTS.md); the harness itself never calls a backend.
  /usr/libexec/PlistBuddy -c "Print :SupabaseURL" "$app/Info.plist"
  xcrun simctl install "$id" "$app"
  xcrun simctl privacy "$id" grant location $BUNDLE
  xcrun simctl privacy "$id" grant calendar $BUNDLE
  xcrun simctl location "$id" set 48.8566,2.3522
}

capture() {
  local id=$(simulator)
  shoot() { # scene lang top scroll wait name
    xcrun simctl terminate "$id" $BUNDLE 2>/dev/null || true
    SIMCTL_CHILD_STORE_SCENE=$1 SIMCTL_CHILD_STORE_LANG=$2 SIMCTL_CHILD_STORE_TOP=$3 SIMCTL_CHILD_STORE_SCROLL=$4 \
      xcrun simctl launch "$id" $BUNDLE >/dev/null
    sleep $5
    mkdir -p "$WORK/shots/$2"
    xcrun simctl io "$id" screenshot --type=png "$WORK/shots/$2/$6.png" 2>/dev/null
  }
  for l in $LANGS; do
    shoot discover $l "" "" 7 warm   # the first launch in a language can keep a few strings of the previous one
    shoot discover $l "" "" 8 discover
    for p in lea maya thomas karim; do shoot discover $l $p "" 8 solo-$p; done
    shoot propose $l "" 500 12 propose
    shoot detail2 $l malik 300 10 malik
    shoot detail2 $l "" 1350 10 icebreaker
    shoot detail2 $l "" 380 10 profile
    shoot detail2 $l maya 420 10 mayav
    rm -f "$WORK/shots/$l/warm.png"
    echo "captured $l"
  done
}

extract() { python3 "$HERE/extract.py" "$WORK" $LANGS; }
compose() { python3 "$HERE/compose.py" "$WORK" "$OUT"; }
feature() { python3 "$HERE/feature.py" "$WORK" "$OUT"; }

case ${1:-all} in
  build) build ;;
  capture) capture ;;
  extract) extract ;;
  compose) compose ;;
  feature) feature ;;
  all) build; capture; extract; compose; feature ;;
  *) echo "usage: $0 [all|build|capture|extract|compose|feature]"; exit 1 ;;
esac
