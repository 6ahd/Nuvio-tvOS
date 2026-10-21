# Siri Remote regression host

This test-only app compiles the production `../../Sources/NvRemote.m` unchanged.
UIKit and `XCUIRemote` deliver real tvOS press events. A small SDL event sink
counts what the legacy core would receive; its parent responder also reproduces
SDL's arrow handling so duplicate forwarding cannot pass unnoticed.

It also compiles the production Swift native-control/image adapter unchanged.
The native fixture exercises real UIKit focus, edge scrolling, safe fallback
for unmarked screens, RGB/alpha image compositing, poster/video-plane ordering
and system-dialog restoration.
It checks all four directions, rapid separate presses, held-button release,
system-dialog focus restoration, Select and Play/Pause. The media engine and
network catalog are deliberately absent, making these input checks deterministic.

```sh
cd tvos/Tests/RemoteHarness
tuist generate --no-open
xcodebuild test -workspace RemoteHarness.xcworkspace -scheme RemoteHarness \
  -destination 'platform=tvOS Simulator,name=Nuvio Remote Regression' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

Use an available tvOS 26+ simulator name. Touchpad gesture recognition and the
feel of the physical Siri Remote still need a device test; simulator directional
presses cannot establish that hardware result.

The separate real-app cases are in `tvos/Remote/NativeApplicationTests.swift`.
Run only that class in the `Remote` scheme with `NV_UI_PREVIEW_BUILD=1`; the
other `RemoteDriver` case is an interactive four-hour command listener.
For Home navigation, copy only the `[native-probe]` lines from the simulator
app's `Library/Caches/nuvio/nuvio.log`, then run
`python3 tvos/Tests/verify-native-navigation.py <trace.log>`.
Both the UI case and the companion trace verification must pass. The trace
comes from the actual UIKit focus system; Release builds exclude this probe.
