# Changelog

Versions follow the legacy app (`2.0.7`) plus an Apple TV beta number. Every IPA
also carries a build number `b<yymmddHHMM>` (the time it was built), shown in its
file name and in tvOS as the bundle version.

## 2.0.7 performance test, b2610202228 (published 2026-10-21)

* Update the shared application core and bundled resources to Nuvio Legacy 2.0.7.
* Use the original GPU renderer by default, keeping native Swift remote focus
  and high-resolution Home posters while disabling full-scene translation.
* Retain Aether 7.40.1, tvOS 26 minimum, indexed subtitles and track-selection fixes.
* Retain experimental whole-scene work as opt-in development code.
* Publish the unsigned IPA with matching source, checksums and validation scope.
* Physical touchpad feel and device performance remain pending owner testing.

## 2.0.6 remote input v2 (2026-10-20)

* Remove the invisible focus grid and delayed recentering.
* Handle all four physical direction presses directly, without forwarding them to SDL again.
* Use native one-shot swipe recognition for one navigation step per gesture.
* Repeat only a physically held direction; stop on release, focus loss or backgrounding.
* Add five real UIKit/XCUIRemote simulator checks in an isolated event-counting host.
* Keep Aether 7.40.1 and the existing media and subtitle fixes.

## 2.0.6 engine update (2026-10-19)

* Update AetherEngine from 7.38.1 to 7.40.1, with pinned LibTrueHD/LibDTSX 3.0.0.
* Explicitly enable TrueHDObjectAudio and DTSXObjectAudio package traits.
* Require tvOS 26, matching the bundled FFmpeg framework metadata.
* Index subtitle timing instead of scanning the entire retained list each frame.
* Retain remote swipe pacing, discrete clicks and playback cancellation fixes.
* Record engine version and commit in the packaged app metadata.

## 2.0.6 remote fix (2026-10-19)

* Replace the dense 14-point remote focus grid with 120-point spacing and a
  bounded swipe repeat cadence (320 ms initial delay, 180 ms repeats).
* Preserve immediate discrete arrow clicks; ignore programmatic recentering
  and focus restoration from the system keyboard; release buttons on deactivation.
* Invalidate pending playback callbacks on stop and guard deferred seeks.
* Keep the selected subtitle when audio/Atmos metadata refreshes.
* Handle lowercase ASS newline escapes as well as uppercase ones.
* Generate configuration successfully without config.env and escape C strings.
* Add host regression tests for swipe timing, subtitle track state and configuration.

## 2.0.6-tvos-beta1 (2026-10-16)

Based on nuvio-native-legacy v2.0.6.

First public beta of the Apple TV port.

### Added
* nuvio-native-legacy running on tvOS 18 and later with the same screens
  as the LG, Samsung and Android TV builds.
* Built in player on the NuvioTVOS engine (AetherEngine 7.38.1):
  4K, HDR10, Dolby Vision, Dolby Atmos, embedded and add-on subtitles, audio
  track choice, resume.
* Settings › Playback › Picture and sound › **Video player**: hand playback to
  Infuse, VLC, Outplayer, nPlayer, VidHub, SenPlayer or Native Player, with the
  same links NuvioTVOS uses.
* **Subtitles in external player** (on by default): waits up to 8 s for add-on
  subtitles and sends them with the stream, preferred language first, up to 8
  (Infuse, SenPlayer, Native Player: several; VLC, VidHub: the best one).
* **TrueHD and DTS:X Atmos** (on by default, tvOS 26+): TrueHD Atmos and DTS:X keep their
  height channels, delivered as Apple Positional Audio, which reaches an Atmos receiver or
  soundbar as Dolby MAT. Off plays them as 7.1.
* Siri Remote driven by the tvOS focus engine: swipes, clicks and held
  directions behave like the system apps.
* Trailers: hero background and detail page trailers (Apple TV trailers and
  IMDb), through the same player as the films.
* Login and settings mirrored outside the cache folder, so they survive tvOS
  clearing the app's caches.

### Fixed
* Black screen of 1 to 3 s before each trailer: trailers no longer switch the TV's
  frame rate and dynamic range (Match Content stays for films and episodes).
* Crash at launch on tvOS 27 (UIScene lifecycle adopted).
* Black logos and artwork (GLES 3 context for non power of two mipmaps).
* Missing WebP artwork (Trakt posters, collection backdrops, poster add-ons,
  badges): decoded with the system ImageIO.

### Known limits
* Outplayer and nPlayer take no subtitle in their link.
* Trakt, Simkl, TMDB and account sync only work in builds made with keys
  (see `config.env.example`).
