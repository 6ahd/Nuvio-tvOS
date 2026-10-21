# Local Swift/UIKit presentation update

> Historical development notes. Whole-scene Swift presentation is experimental
> and disabled by default in the performance release. See [README](README.md).

This update is local and has not been pushed or released on GitHub. Device
testing and the owner's approval are required before publication.

## Migration scope

UIKit now owns the visible scene: UILabel text, UIImageView artwork and native
decoration views replace the tvOS GL presentation passes. The existing design
coordinates, screen state, layout decisions, services and actions remain in the
shared C core. This is a native presentation backend, not a complete rewrite of
every screen controller or all application code in Swift.

The adapter covers the 54 presentation modes in Nuvio 2.0.7, including clipped
posters, artwork crossfades, dialogs, settings, profile screens, video holes,
offscreen thumbnails and diagnostic pixel readback. The five GL output scaling modes use native image presentation; the whole UIKit scene already renders independently of the legacy low-resolution framebuffer. Native text uses logical
Unicode and bundled fonts. Cards retain the original RGB/alpha behavior. QR
codes use nearest sampling; artwork uses smooth filtering. Some decorative
shader effects, including glass lens and procedural backgrounds, are native
approximations and require visual acceptance on the TV.

Native focus uses the original selected item's geometry. Custom Select actions
execute once, on release, and do not also send SDL Select. Unsupported internal
widgets retain the existing input receiver. Physical Siri Remote swipe pacing
and the feel of movement still require a real Apple TV test.

## Validation

The local component harness passed 22 simulator UI tests on tvOS 26.5, covering
four directions, held-key cleanup, selection, system dialogs, offscreen rows,
artwork colors, alpha, clipping, Arabic text, QR edges, video-plane order,
attachment replacement, image crossfades and native pixel readback.

The actual application has separate, finite UI acceptance tests in
`tvos/Remote/NativeApplicationTests.swift`. They run only against a test build
with `NV_UI_PREVIEW_BUILD=1`, local bundled artwork and no account sync. The
Release IPA must contain neither preview account bypass nor forced routes.
Final build and acceptance results are recorded with the local IPA.

Actual application acceptance rendered 12 real screens using bundled artwork.
The Home navigation case also passed with real XCUIRemote directions and five
verified UIKit focus transitions: hero, first row, next poster, next row, and
back to the selected column. The navigation fixture omits the empty friends row
because that internal widget deliberately retains the legacy input receiver.
The companion `tvos/Tests/verify-native-navigation.py` validates the focus trace.
The test observes UIKit focus through a debug-only scene identifier because
the custom sibling controls are not reliably represented by XCTest's focus
attribute. This does not replace the pending physical touchpad test.

The catalogue on a user's account, live services, sustained video playback,
physical remote behavior and exact visual parity have not been established by
these simulator checks. No performance percentage or frame-rate guarantee is
claimed.

## Runtime

The unsigned arm64 IPA requires signing and tvOS 26 or later. Playback remains
on the pinned AetherEngine 7.40.1 integration. Native presentation revision is
2; remote input revision is 4. `NUVIO_SWIFT_SCENE=0` selects the prior rendering
backend for local diagnosis.
