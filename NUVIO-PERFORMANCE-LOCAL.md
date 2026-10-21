# Nuvio 2.0.7 — scrolling performance pre-release

This patch addresses the owner's report that poster and menu navigation became
heavier after the whole-scene Swift presentation update. It retains the existing
design, native UIKit focus, shared 2.0.7 application logic and Aether 7.40.1.

The performance candidate disables whole-scene C-command-to-UIView translation
by default. It uses the existing GPU renderer with native Swift/UIKit focus and
bounded high-resolution poster surfaces. This removes the additional full-scene
view hierarchy, duplicate image registry and CPU decorative rasterization from
the normal path. The full Swift scene remains experimental and opt-in through
`NUVIO_SWIFT_SCENE=1`; it is not the presentation default of this IPA.

The experimental path has bounded display-link pacing, cached decoration and
lighter soft-gradient backing stores. It is retained for development, rather
than represented as a proven performance improvement on physical Apple TV.

Draw slots create only the image, text or decoration views they use. Flat fills
use a layer background. Image content is retained across geometry changes,
visibility is not toggled as a side effect of movement, and decorative caches
ignore shader inputs that do not affect the decoration being painted.

Offscreen command lists mutate in place, preventing an array copy for each
appended command. One scratch hierarchy serves snapshots without keeping a view
tree per thumbnail. Native accessibility labels share one text index per frame,
and unchanged view ordering avoids repeated hierarchy traversal.

The local acceptance checks cover 23 native component cases and actual UIKit
focus across Home poster rows with no renderer override. The extended default-
renderer screenshot sweep was stopped to release simulator resources and is not
reported as a passing 12-screen run. The separate opt-in scene has its own
12-screen tests from the development iterations. The device
IPA is built in Release for arm64 and excludes preview routing and focus probes.
Opt-in `NUVIO_SCENE_PERF=1` reports aggregate renderer timings only.

Simulator runs are useful for finding regressions but are sensitive to other
simulators and host load. They do not establish a physical Apple TV frame rate
or a guaranteed percentage improvement. Touchpad feel and streaming still need
the owner's device test. This is native presentation over the shared C core;
the application logic has not been rewritten in Swift.

The owner authorized public publication of this candidate on 2026-10-21.
It remains a test release; public availability does not imply completed
physical-device acceptance. Private configuration and earlier Git history are
excluded from this public source snapshot.
