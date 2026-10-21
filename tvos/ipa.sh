#!/bin/bash
# Release build for a real Apple TV, packed as an UNSIGNED .ipa (sign and
# install it with Sideloadly or similar). Output: dist/NuvioLegacy-AppleTV-<ver>.ipa
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(dirname "$PWD")"
export PATH="/opt/homebrew/bin:$PATH"
bash prepare.sh > prepare.log 2>&1 || { echo "PREPARE FAILED"; tail -20 prepare.log; exit 1; }
ARCH="$PWD/build-dev/DexLegacy.xcarchive"
rm -rf "$ARCH"
xcodebuild archive -workspace DexLegacy.xcworkspace -scheme DexLegacy -configuration Release \
  -destination 'generic/platform=tvOS' -archivePath "$ARCH" -derivedDataPath build-dev \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_ENTITLEMENTS="" \
  > ipa-build.log 2>&1 || { grep -E "error:|Undefined" ipa-build.log | sort -u | head -40; echo "ARCHIVE FAILED"; exit 1; }
APP="$ARCH/Products/Applications/DexLegacy.app"
[ ! -d "$REPO/licenses" ] || cp -R "$REPO/licenses" "$APP/Licenses"
# The version is the legacy release the build is made from (LEGACY_TAG).
if [ -f "$REPO/legacy/.nv-merged" ] && [ -f "$PWD/legacy-release.json" ]; then
  # A merged source archive may retain an older upstream .git directory.
  # Its release manifest describes the source actually being built.
  LTAG=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PWD/legacy-release.json")
else
  LTAG=$(git -C "$REPO/legacy" describe --tags --exact-match 2>/dev/null || true)
fi
[ -n "$LTAG" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${LTAG#v}" "$APP/Info.plist"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist")
# Every IPA gets its own build number (date and time), so builds are told apart
# in Sideloadly and in Settings > Apps on the Apple TV.
BUILD="${BUILD:-$(TZ=Asia/Riyadh date +%y%m%d%H%M)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Info.plist"
python3 - "$APP/Info.plist" "$PWD/engine-release.json" <<'PYCODE'
import json, plistlib, sys
from pathlib import Path
path = Path(sys.argv[1])
metadata = plistlib.loads(path.read_bytes())
release = json.loads(Path(sys.argv[2]).read_text())
metadata['NuvioAetherVersion'] = release['version']
metadata['NuvioAetherCommit'] = release['commit']
metadata['NuvioAetherTraits'] = release['traits']
metadata['NuvioRemoteInputVersion'] = 4
metadata['NuvioNativeUIVersion'] = 3
metadata['NuvioPresentationMode'] = 'native-focus-original-renderer'
metadata['NuvioSwiftSceneDefaultEnabled'] = False
path.write_bytes(plistlib.dumps(metadata, fmt=plistlib.FMT_BINARY))
PYCODE
VER="$VER-b$BUILD"
TMP="$PWD/build-dev/ipa"; rm -rf "$TMP"; mkdir -p "$TMP/Payload" "$REPO/dist"
cp -R "$APP" "$TMP/Payload/"
(cd "$TMP" && zip -qry "$REPO/dist/NuvioLegacy-AppleTV-$VER.ipa" Payload)
ls -lh "$REPO/dist/NuvioLegacy-AppleTV-$VER.ipa"
