# Third-party software

This Apple TV port is a modified version of other people's work. This file lists what
it is built from and under which terms. The full GPLv3 text is in
[LICENSE](LICENSE).

## Source this project modifies

| Project | Where it comes from | License |
|---|---|---|
| nuvio-native-legacy v2.0.7 (shared app logic and layout) | https://github.com/iqui27/nuvio-native-legacy | GPLv3 |
| NuvioTVOS (playback engine package layout, external player link formats) | https://github.com/bobsupra/NuvioTVOS | GPLv3 |

`prepare.sh` downloads the legacy app and AetherEngine at pinned versions.
NuvioTVOS remains a reference for the platform layout and external player links. The changes made to
nuvio-native-legacy are all in [patches/legacy-tvos.patch](patches/legacy-tvos.patch);
everything under `tvos/` is new code for Apple TV.

## Libraries in the app

| Library | License |
|---|---|
| [AetherEngine 7.40.1](https://github.com/superuser404notfound/AetherEngine) | LGPLv3 with an App Store / DRM exception |
| [FFmpegBuild 3.7.1](https://github.com/superuser404notfound/FFmpegBuild) | LGPL 2.1 or later; dav1d BSD 2 Clause; zimg WTFPL; libzvbi parts MIT (see that folder's `LICENSES/`) |
| LibDovi, LibTrueHD, LibDTSX, SMBClient (AetherEngine dependencies) | see each repository |
| SDL2, SDL2_image, SDL2_ttf | zlib |
| FreeType, HarfBuzz (bundled with SDL2_ttf) | FreeType License, MIT |
| libcurl | curl license (MIT style) |
| Mbed TLS | Apache 2.0 |
| Lucide icons (in nuvio-native-legacy) | ISC |
| Snapdragon Game Super Resolution (legacy GL fallback) | [SGSR license](licenses/SGSR-LICENSE.txt) |
| IBM Plex Sans Arabic (subtitle and interface font) | SIL OFL 1.1 (`legacy/deploy/app/fonts/OFL-IBMPlexSansArabic.txt`) |

Fonts put in `fonts-extra/` for a private build are not part of this repository and keep their own terms.

## Names and logos

"Nuvio", its logo and wordmark belong to their original authors. The GPL covers
code, not names or branding. This Apple TV port is unofficial and is not
affiliated with or endorsed by the Nuvio projects. The app icon and the artwork inside the app come from nuvio-native-legacy
unchanged.

Artwork shown at runtime (TMDB, Trakt, add-on images) belongs to its owners.
