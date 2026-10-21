#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
  "$HERE/remote-timing.c" -o "$WORK/remote-timing"
"$WORK/remote-timing"
cc -std=c11 -Wall -Wextra -Werror -DNV_TVOS -fsanitize=address,undefined \
  "$HERE/artwork-size.c" "$HERE/../../legacy/src/artetamanho.c" -o "$WORK/artwork-size"
"$WORK/artwork-size"
cc -std=gnu11 -O1 -g -ffunction-sections -fdata-sections -Wl,-dead_strip \
  -fsanitize=address,undefined \
  -I"$HERE/../Frameworks/NvDeps.xcframework/tvos-arm64/Headers" \
  "$HERE/video-tracks.c" -o "$WORK/video-tracks"
"$WORK/video-tracks"
swiftc -O -module-cache-path "$WORK/swift-cache" \
  "$HERE/../Sources/SubtitleWindowIndex.swift" "$HERE/SubtitleWindowIndexTests.swift" \
  -o "$WORK/subtitle-window"
"$WORK/subtitle-window"
bash "$HERE/../generate-config.sh" "$WORK/missing.env" "$WORK/empty.h" v2.0.6
grep -q '#define NV_SIMKL_APP "Nuvio"' "$WORK/empty.h"
grep -q '#define NV_SUPABASE_URL ""' "$WORK/empty.h"
printf 'NV_SIMKL_APP=Name "quoted" \\path\r\n' > "$WORK/test.env"
bash "$HERE/../generate-config.sh" "$WORK/test.env" "$WORK/config.h" v2.0.6
cat > "$WORK/config-test.c" <<'C'
#include <assert.h>
#include <string.h>
#include "config.h"
int main(void) {
    assert(!strcmp(NV_SIMKL_APP, "Name \"quoted\" \\path"));
    assert(!strcmp(NV_VERSAO, "2.0.6"));
}
C
cc -Wall -Wextra -Werror "$WORK/config-test.c" -o "$WORK/config-test"
"$WORK/config-test"
echo 'config generation: PASS (missing file, defaults, quotes, backslashes, CRLF)'
