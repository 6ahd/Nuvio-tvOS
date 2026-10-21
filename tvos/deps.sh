#!/bin/bash
# Builds the native libraries Dex Legacy needs on Apple TV as static libs and
# packs them into one XCFramework (device + simulator):
#   SDL2 + SDL2main, SDL2_image (ImageIO backend), SDL2_ttf (vendored FreeType
#   and HarfBuzz), libcurl (mbedTLS).
# Output: tvos/Frameworks/NvDeps.xcframework (run once, ~15 min)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/.deps"
OUT="$HERE/Frameworks"
MIN_TVOS=17.0
export PATH="/opt/homebrew/bin:$PATH"
mkdir -p "$WORK/src" "$OUT"
cd "$WORK/src"

fetch() { # name url tag [recursive]
  [ -d "$1" ] && return 0
  if [ "${4:-}" = rec ]; then
    git clone -q --depth 1 --branch "$3" --recurse-submodules --shallow-submodules "$2" "$1"
  else
    git clone -q --depth 1 --branch "$3" "$2" "$1"
  fi
}
fetch SDL       https://github.com/libsdl-org/SDL.git        release-2.30.9
fetch SDL_image https://github.com/libsdl-org/SDL_image.git  release-2.8.2
fetch SDL_ttf   https://github.com/libsdl-org/SDL_ttf.git    release-2.22.0 rec
fetch curl      https://github.com/curl/curl.git             curl-8_11_1
fetch mbedtls   https://github.com/Mbed-TLS/mbedtls.git      v3.6.2 rec

build_platform() { # sysroot
  local SDK="$1" P="$WORK/install-$1" B="$WORK/build-$1"
  local COMMON=(-G Ninja -DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_OSX_SYSROOT="$SDK"
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_TVOS
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
    -DCMAKE_INSTALL_PREFIX="$P" -DCMAKE_PREFIX_PATH="$P"
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    -DCMAKE_FIND_ROOT_PATH="$P" -DSDL2_DIR="$P/lib/cmake/SDL2"
    -DSDL2_LIBRARY="$P/lib/libSDL2.a" -DSDL2_INCLUDE_DIR="$P/include/SDL2" -DSDL2_MAIN_LIBRARY="$P/lib/libSDL2main.a"
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH)
  mkdir -p "$B"
  step() { [ -f "$B/$1.ok" ]; }
  done_() { touch "$B/$1.ok"; }

  step sdl || { cmake -S SDL -B "$B/sdl" "${COMMON[@]}" -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF
  cmake --build "$B/sdl" && cmake --install "$B/sdl" && done_ sdl; }

  step img || cmake -S SDL_image -B "$B/img" "${COMMON[@]}" -DSDL2IMAGE_SAMPLES=OFF -DSDL2IMAGE_TESTS=OFF \
    -DSDL2IMAGE_BACKEND_IMAGEIO=ON -DSDL2IMAGE_DEPS_SHARED=OFF -DSDL2IMAGE_VENDORED=OFF \
    -DSDL2IMAGE_AVIF=OFF -DSDL2IMAGE_JXL=OFF -DSDL2IMAGE_TIF=OFF -DSDL2IMAGE_WEBP=OFF
  step img || { cmake --build "$B/img" && cmake --install "$B/img" && done_ img; }

  step ttf || cmake -S SDL_ttf -B "$B/ttf" "${COMMON[@]}" -DSDL2TTF_SAMPLES=OFF -DSDL2TTF_VENDORED=ON \
    -DSDL2TTF_HARFBUZZ=ON -DSDL2TTF_INSTALL=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON \
    -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_ZLIB=OFF
  step ttf || { cmake --build "$B/ttf" && cmake --install "$B/ttf" && done_ ttf; }

  step mbedtls || { cmake -S mbedtls -B "$B/mbedtls" "${COMMON[@]}" -DENABLE_PROGRAMS=OFF \
    -DENABLE_TESTING=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=OFF -DUSE_STATIC_MBEDTLS_LIBRARY=ON \
    -DMBEDTLS_FATAL_WARNINGS=OFF
  cmake --build "$B/mbedtls" && cmake --install "$B/mbedtls" && done_ mbedtls; }

  step curl || cmake -S curl -B "$B/curl" "${COMMON[@]}" -DBUILD_CURL_EXE=OFF -DBUILD_TESTING=OFF \
    -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF -DENABLE_CURL_MANUAL=OFF \
    -DCURL_USE_SECTRANSP=OFF -DCURL_USE_MBEDTLS=ON -DCURL_USE_OPENSSL=OFF \
    -DMBEDTLS_INCLUDE_DIRS="$P/include" -DMBEDTLS_LIBRARY="$P/lib/libmbedtls.a" \
    -DMBEDX509_LIBRARY="$P/lib/libmbedx509.a" -DMBEDCRYPTO_LIBRARY="$P/lib/libmbedcrypto.a" \
    -DCURL_CA_BUNDLE=none -DCURL_CA_PATH=none -DCURL_USE_LIBPSL=OFF -DUSE_LIBIDN2=OFF \
    -DCURL_ZSTD=OFF -DCURL_BROTLI=OFF -DUSE_NGHTTP2=OFF -DCURL_USE_LIBSSH2=OFF \
    -DCURL_DISABLE_LDAP=ON -DENABLE_UNIX_SOCKETS=OFF -DCURL_CA_FALLBACK=OFF
  step curl || { cmake --build "$B/curl" && cmake --install "$B/curl" && done_ curl; }

  # One static archive with everything (vendored FreeType/HarfBuzz included).
  local LIBS
  LIBS=$(find "$P/lib" "$B/ttf" -name "*.a" | grep -v -E "SDL2_test|test" | sort -u)
  echo "Merging for $SDK:"; echo "$LIBS"
  libtool -static -o "$P/libNvDeps.a" $LIBS 2>/dev/null
  # Headers: <SDL2/...>, <curl/...>
  rm -rf "$P/hdr"; mkdir -p "$P/hdr"
  cp -R "$P/include/SDL2" "$P/hdr/SDL2"
  cp -R "$P/include/curl" "$P/hdr/curl"
}

build_platform appletvos
build_platform appletvsimulator

rm -rf "$OUT/NvDeps.xcframework"
xcodebuild -create-xcframework \
  -library "$WORK/install-appletvos/libNvDeps.a" -headers "$WORK/install-appletvos/hdr" \
  -library "$WORK/install-appletvsimulator/libNvDeps.a" -headers "$WORK/install-appletvsimulator/hdr" \
  -output "$OUT/NvDeps.xcframework"
echo "DEPS OK: $OUT/NvDeps.xcframework"
