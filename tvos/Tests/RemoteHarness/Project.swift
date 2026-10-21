import ProjectDescription

let app: Target = .target(
    name: "RemoteHarness", destinations: [.appleTv], product: .app,
    bundleId: "cc.dexworld.remote-regression", deploymentTargets: .tvOS("26.0"),
    infoPlist: .extendingDefault(with: [
        "UIApplicationSceneManifest": ["UIApplicationSupportsMultipleScenes": false],
        "UILaunchScreen": [:],
    ]),
    sources: ["Harness.m", "../../Sources/NvRemote.m", "../../Sources/NvNativeUI.swift",
              "../../Sources/NvNativePosters.swift", "../../Sources/NvSwiftScene.swift",
              "../../Sources/NvScenePrimitives.swift", "../../Sources/NvSceneResources.swift",
              "SwiftSceneFixture.swift"],
    dependencies: [.sdk(name: "UIKit", type: .framework)],
    settings: .settings(base: [
        "HEADER_SEARCH_PATHS": ["$(SRCROOT)/../../Frameworks/NvDeps.xcframework/tvos-arm64-simulator/Headers"],
        "CLANG_ENABLE_OBJC_ARC": "YES", "CODE_SIGNING_ALLOWED": "NO",
        "SWIFT_VERSION": "5.0", "SWIFT_OBJC_BRIDGING_HEADER": "../../Sources/NvBridge.h",
    ])
)
let tests: Target = .target(
    name: "RemoteHarnessTests", destinations: [.appleTv], product: .uiTests,
    bundleId: "cc.dexworld.remote-regression.tests", deploymentTargets: .tvOS("26.0"),
    infoPlist: .default, sources: ["RemoteTests.swift", "NativeUITests.swift", "SwiftSceneTests.swift"], dependencies: [.target(name: "RemoteHarness")],
    settings: .settings(base: ["SWIFT_VERSION": "5.0", "TEST_TARGET_NAME": "RemoteHarness"])
)
let project = Project(name: "RemoteHarness", targets: [app, tests])
