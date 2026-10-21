#!/bin/bash
# Build for the Apple TV simulator, install, launch and take a screenshot.
# usage: sim-run.sh [build-only]     (SIM_DEVICE=<udid> to pick a simulator)
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"
# First Apple TV simulator on tvOS 18 or later (older runtimes are below the deployment target).
DEV="${SIM_DEVICE:-$(xcrun simctl list devices available | awk '/^-- tvOS /{ok=($3+0>=18)} ok && /Apple TV|NuvioLegacy TV/' | grep -m1 -oE '[0-9A-F-]{36}')}"
[ -n "$DEV" ] || { echo "no Apple TV simulator: create one in Xcode > Devices"; exit 1; }
bash prepare.sh > prepare.log 2>&1 || { echo "PREPARE FAILED"; tail -20 prepare.log; exit 1; }
xcodebuild -workspace DexLegacy.xcworkspace -scheme DexLegacy -configuration Debug \
  -destination "id=$DEV" -derivedDataPath build-sim CODE_SIGNING_ALLOWED=NO build > build.log 2>&1
rc=$?
grep -E "error:|Undefined symbols" build.log | sort -u | head -40
grep -E "BUILD (SUCCEEDED|FAILED)" build.log | tail -1
[ $rc -ne 0 ] && exit 1
[ "${1:-}" = build-only ] && exit 0
APP=build-sim/Build/Products/Debug-appletvsimulator/DexLegacy.app
xcrun simctl boot "$DEV" 2>/dev/null
xcrun simctl terminate "$DEV" cc.dexworld.dexlegacy 2>/dev/null
xcrun simctl install "$DEV" "$APP" || exit 1
mkdir -p shots
xcrun simctl launch --console-pty "$DEV" cc.dexworld.dexlegacy > run.log 2>&1 &
sleep "${WAIT:-25}"
xcrun simctl io "$DEV" screenshot shots/boot.png >/dev/null 2>&1 && echo "screenshot: tvos/shots/boot.png"
