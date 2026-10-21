import ProjectDescription

// Dex Legacy for Apple TV: an unofficial tvOS port of the nuvio-native-legacy
// C client (same UI, same code as its LG/Samsung/Android builds), playing
// through the NuvioTVOS engine (AetherEngine).
//
// Layout (all under port/):
//   ../legacy/              nuvio-native-legacy at v2.0.7 + patches/legacy-tvos.patch (prepare.sh)
//   ../vendor/AetherEngine-7.40.1/ playback engine pinned by prepare_engine.py
//   tvos/Frameworks/        NvDeps.xcframework (deps.sh)
//   tvos/Generated/         nv_config.h (from config.env, never committed)
//   tvos/Sources/           Objective-C / Swift platform layer

let bundleID = "cc.dexworld.dexlegacy"

let cFlags: [String] = [
    "$(inherited)",
    "-DNV_TVOS=1",
    "-include", "$(SRCROOT)/Generated/nv_config.h",
    "-include", "$(SRCROOT)/Sources/nv_prefix.h",
    "-w",
]

let app: Target = .target(
    name: "DexLegacy",
    destinations: [.appleTv],
    product: .app,
    productName: "DexLegacy",
    bundleId: bundleID,
    deploymentTargets: .tvOS("26.0"),   // The bundled FFmpeg frameworks declare tvOS 26
    infoPlist: .file(path: "Info.plist"),
    sources: [
        "../legacy/src/*.c",
        "../legacy/src/dts/*.c",
        "Sources/**/*.m",
        "Sources/**/*.swift",
    ],
    resources: [
        .folderReference(path: "../legacy/deploy/app/art"),
        .folderReference(path: "../legacy/deploy/app/fonts"),
        "Assets.xcassets",
    ],
    scripts: [
        // Same post step as NuvioTVOS: the FFmpeg frameworks AetherEngine
        // brings must be thinned and present in the simulator .app.
        .post(
            script: "/bin/sh \"${SRCROOT}/Scripts/thin_aether_simulator_frameworks.sh\"",
            name: "Thin Aether Simulator Frameworks",
            basedOnDependencyAnalysis: false
        ),
    ],
    entitlements: .file(path: "DexLegacy.entitlements"),
    dependencies: [
        .target(name: "DexLegacyTopShelf"),
        .package(product: "AetherEngine"),
        .xcframework(path: "Frameworks/NvDeps.xcframework"),
        .sdk(name: "OpenGLES", type: .framework),
        .sdk(name: "UIKit", type: .framework),
        .sdk(name: "AVFoundation", type: .framework),
        .sdk(name: "AudioToolbox", type: .framework),
        .sdk(name: "CoreAudio", type: .framework),
        .sdk(name: "CoreGraphics", type: .framework),
        .sdk(name: "CoreHaptics", type: .framework),
        .sdk(name: "GameController", type: .framework),
        .sdk(name: "Foundation", type: .framework),
        .sdk(name: "Metal", type: .framework),
        .sdk(name: "QuartzCore", type: .framework),
        .sdk(name: "ImageIO", type: .framework),
        .sdk(name: "MobileCoreServices", type: .framework),
        .sdk(name: "UniformTypeIdentifiers", type: .framework),
        .sdk(name: "Security", type: .framework),
        .sdk(name: "SystemConfiguration", type: .framework),
        .sdk(name: "CoreFoundation", type: .framework),
        .sdk(name: "CoreBluetooth", type: .framework),
        .sdk(name: "AVKit", type: .framework),
        .sdk(name: "TVServices", type: .framework),
        .sdk(name: "CoreMedia", type: .framework),
        .sdk(name: "CoreVideo", type: .framework),
        .sdk(name: "VideoToolbox", type: .framework),
        .sdk(name: "z", type: .library),
        .sdk(name: "iconv", type: .library),
        .sdk(name: "c++", type: .library),
    ],
    settings: .settings(base: [
        "HEADER_SEARCH_PATHS": ["$(inherited)", "$(SRCROOT)/../legacy/src"],
        "OTHER_CFLAGS": .array(cFlags),
        "GCC_C_LANGUAGE_STANDARD": "gnu11",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "ENABLE_BITCODE": "NO",
        "DEAD_CODE_STRIPPING": "YES",
        "TARGETED_DEVICE_FAMILY": "3",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "SWIFT_VERSION": "5.0",
        "SWIFT_OBJC_BRIDGING_HEADER": "Sources/NvBridge.h",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "OTHER_LDFLAGS": ["$(inherited)", "-ObjC"],
        "CODE_SIGN_STYLE": "Automatic",
    ])
)

// The Top Shelf: Continue Watching above the Apple TV home screen icons
// (TopShelf/ContentProvider.swift), fed by the app through the app group.
let topShelf: Target = .target(
    name: "DexLegacyTopShelf",
    destinations: [.appleTv],
    product: .tvTopShelfExtension,
    bundleId: "\(bundleID).topshelf",
    deploymentTargets: .tvOS("26.0"),
    infoPlist: .file(path: "TopShelf/Info.plist"),
    sources: ["TopShelf/**/*.swift"],
    entitlements: .file(path: "TopShelf/TopShelf.entitlements"),
    dependencies: [.sdk(name: "TVServices", type: .framework)],
    settings: .settings(base: ["SWIFT_VERSION": "5.0", "CODE_SIGN_STYLE": "Automatic",
                               "TARGETED_DEVICE_FAMILY": "3"])
)

// Test-only: drives the Siri Remote in the simulator from command files
// (Remote/RemoteDriver.swift). Never part of the shipped app.
let remote: Target = .target(
    name: "Remote",
    destinations: [.appleTv],
    product: .uiTests,
    bundleId: "\(bundleID).remote",
    deploymentTargets: .tvOS("26.0"),
    infoPlist: .default,
    sources: ["Remote/**/*.swift"],
    dependencies: [.target(name: "DexLegacy")],
    settings: .settings(base: ["GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "DexLegacy",
                               "SWIFT_VERSION": "5.0"])
)

let project = Project(
    name: "DexLegacy",
    organizationName: "DexWorld",
    packages: [
        // prepare_engine.py pins the release and enables object audio traits.
        .local(path: "../vendor/AetherEngine-7.40.1"),
    ],
    targets: [app, topShelf, remote],
    schemes: [
        .scheme(
            name: "Remote",
            shared: true,
            buildAction: .buildAction(targets: ["DexLegacy", "Remote"]),
            testAction: .targets(["Remote"], configuration: "Debug")
        ),
        .scheme(
            name: "DexLegacy",
            shared: true,
            buildAction: .buildAction(targets: ["DexLegacy"]),
            runAction: .runAction(configuration: "Debug"),
            archiveAction: .archiveAction(configuration: "Release")
        ),
    ]
)
