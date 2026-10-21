# Nuvio 2.0.7 — local Apple TV update

Upstream: [v2.0.7](https://github.com/iqui27/nuvio-native-legacy/releases/tag/v2.0.7),
commit `5eddbe92f272a6f23d459b15354c6657bbf133d1`.

The shared application source and relevant bundled resources are updated from
2.0.6 to 2.0.7. Apple TV retains the AetherEngine 7.40.1 integration, external
player choices, subtitle/track fixes, persistent state, high-resolution artwork
and native remote controls. Native scene rendering is described in
[SWIFT-PRESENTATION-2026-10-20.md](SWIFT-PRESENTATION-2026-10-20.md).

The new upstream settings are retained alongside the Apple TV settings. The
three Apple TV option IDs and their parallel defaults/keys remain together,
preserving the previous device settings mapping. The new Arabic table includes
translations for all six Apple TV-specific strings and matches the shared
6,210-entry translation table in key order.

`tvos/legacy-release.json` records the exact upstream release. `prepare.sh`
defaults to v2.0.7. The rebased `patches/legacy-tvos.patch` has been applied to
clean upstream 2.0.7 sources and checked to reproduce the 852 local source files
byte for byte. Merged source checkouts use the manifest for the IPA version,
including when their retained upstream Git directory still names an older tag.

The local test build uses bundled sample artwork and disables account sync,
first-run introductions and update notices. Those preview branches and the
debug-only focus probe are absent from the Release IPA. No user account is
created or changed for the tests.

This file records the initial local integration. The owner subsequently
authorized publication of the performance candidate as a pre-release; see
README.md for the current renderer default and testing scope.
