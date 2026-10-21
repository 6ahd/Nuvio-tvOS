#!/bin/bash
# Fetches the two upstream sources, applies the tvOS patch, writes
# Generated/nv_config.h from config.env and generates the Xcode project.
#   legacy/               iqui27/nuvio-native-legacy at LEGACY_TAG
#   vendor/AetherEngine-<version>/  pinned playback engine and enabled traits
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
# The legacy release the patch is made against. To move to a new release see
# UPDATING.md (rebase the patch, then change this tag).
LEGACY_TAG="${LEGACY_TAG:-v2.0.7}"
export PATH="/opt/homebrew/bin:$PATH"
cd "$REPO"

if [ -f legacy/.nv-merged ]; then
  # private-full branch: legacy/ is already the patched source, kept in git.
  echo "legacy: merged copy ($(cat legacy/.nv-merged))"
elif [ ! -d legacy/.git ]; then
  git clone -q --depth 1 --branch "$LEGACY_TAG" https://github.com/iqui27/nuvio-native-legacy.git legacy
fi
# An existing clone of another release is moved to LEGACY_TAG.
if [ ! -f legacy/.nv-merged ] && [ "$(git -C legacy describe --tags --exact-match 2>/dev/null)" != "$LEGACY_TAG" ]; then
  git -C legacy fetch -q --depth 1 origin tag "$LEGACY_TAG" &&
  git -C legacy checkout -q -f "$LEGACY_TAG" || { echo "cannot get legacy $LEGACY_TAG"; exit 1; }
fi
[ -f legacy/.nv-merged ] || ( cd legacy && git checkout -q -- . && git clean -fdq src &&
  git apply --whitespace=nowarn "$REPO/patches/legacy-tvos.patch" )
echo "legacy $LEGACY_TAG patched"

python3 "$HERE/prepare_engine.py" "$REPO"

[ -f "$REPO/config.env" ] || echo "warning: no config.env (copy config.env.example); account features will not work"
bash "$HERE/generate-config.sh" "$REPO/config.env" "$HERE/Generated/nv_config.h" "$LEGACY_TAG"
# Private subtitle/interface fonts (the Dex Hub ones), never in git: put the
# .ttf files in fonts-extra/ at the repo root. They ship in the app's
# fonts/extra/ and NV_FONTES_EXTRA adds their families to the font lists.
EXTRA_DST="$REPO/legacy/deploy/app/fonts/extra"
rm -rf "$EXTRA_DST"
if ls "$REPO"/fonts-extra/*.ttf >/dev/null 2>&1; then
  mkdir -p "$EXTRA_DST"
  cp "$REPO"/fonts-extra/*.ttf "$EXTRA_DST"/
  echo '#define NV_FONTES_EXTRA 1' >> "$HERE/Generated/nv_config.h"
  echo "fonts-extra: $(ls "$EXTRA_DST" | wc -l | tr -d ' ') font files"
fi
cd "$HERE" && tuist generate --no-open
