#!/bin/bash
# Test helper: drives the Siri Remote in the simulator from command files.
# Commands go to <repo>/.remote/cmd/NNN.txt (see Remote/RemoteDriver.swift);
# screenshots land in <repo>/.remote/shots. usage: remote-start.sh [build-only]
cd "$(dirname "$0")"
REPO="$(dirname "$PWD")"
export PATH="/opt/homebrew/bin:$PATH"
DEV="${SIM_DEVICE:-$(xcrun simctl list devices available | grep -m1 "Apple TV" | grep -oE '[0-9A-F-]{36}')}"
mkdir -p "$REPO/.remote/cmd" "$REPO/.remote/shots"
xcodebuild build-for-testing -workspace DexLegacy.xcworkspace -scheme Remote -configuration Debug \
  -destination "id=$DEV" -derivedDataPath build-sim CODE_SIGNING_ALLOWED=NO > remote-build.log 2>&1
grep -E "error:|TEST BUILD" remote-build.log | tail -5
[ "${1:-}" = build-only ] && exit 0
pkill -f "test-without-building.*Remote" 2>/dev/null
TEST_RUNNER_NV_REMOTE_DIR="$REPO/.remote" nohup xcodebuild test-without-building \
  -workspace DexLegacy.xcworkspace -scheme Remote -destination "id=$DEV" \
  -derivedDataPath build-sim CODE_SIGNING_ALLOWED=NO > remote-test.log 2>&1 &
echo "remote driver pid $!"
