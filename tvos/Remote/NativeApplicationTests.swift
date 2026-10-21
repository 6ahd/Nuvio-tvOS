import XCTest

// Real application acceptance against its bundled catalogue, not a fake view
// hierarchy. NV_UI_PREVIEW_BUILD must be enabled for this simulator test build;
// the Release IPA contains neither account bypass nor forced-screen routing.
final class NativeApplicationTests: XCTestCase {
    private func launch(_ screen: String, traceFocus: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "cc.dexworld.dexlegacy")
        app.launchEnvironment = ["NUVIO_UI_PREVIEW": "1", "NUVIO_UI_PREVIEW_SCREEN": screen,
                                 "NUVIO_SWIFT_SCENE": "1", "NUVIO_NATIVE_UI": "1"]
        if traceFocus {
            app.launchEnvironment["NUVIO_NATIVE_UI_STATS"] = "1"
            app.launchEnvironment["NUVIO_UI_PREVIEW_POSTER_ROWS"] = "1"
        }
        app.launch()
        return app
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        // Also clean up when an assertion stops a test before its last line.
        let app = XCUIApplication(bundleIdentifier: "cc.dexworld.dexlegacy")
        if app.state != .notRunning { app.terminate() }
    }

    func testRealScreensPresentNativeContent() {
        let screens = [("home", "home"), ("detail", "detalhe"), ("search", "busca"),
                       ("library", "biblioteca"), ("settings", "ajustes"), ("menu", "menu"),
                       ("explore", "explorar"), ("guide", "guia"), ("profile", "perfil"),
                       ("addons", "addons"), ("plugins", "plugins"), ("agenda", "agenda")]
        for (route, name) in screens {
            let app = launch(route)
            XCTAssertTrue(app.otherElements["swift-presentation-\(name)"].waitForExistence(timeout: 20), route)
            XCTAssertGreaterThan(app.staticTexts.count, 0, route)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "native-application-\(route)"; shot.lifetime = .keepAlways; add(shot)
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }
    func testRealHomeNavigationKeepsFocusAcrossRows() throws {
        let app = launch("home", traceFocus: true)
        let scene = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@",
            "swift-presentation-home-native-control-")).firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 20))
        // UIKit focus IDs are checked by verify-native-navigation.py against
        // the app's debug trace. The SDL sibling controls are not exposed by
        // this runtime's XCTest accessibility tree. Each press below still
        // comes from XCUIRemote and passes through the real UIKit focus engine.
        XCTAssertGreaterThan(app.staticTexts.count, 0)
        let buttons: [XCUIRemote.Button] = [.down, .right, .down, .up]
        var identities = [scene.identifier]
        for button in buttons {
            let before = scene.identifier
            XCUIRemote.shared.press(button)
            expectation(for: NSPredicate(format: "identifier != %@", before), evaluatedWith: scene)
            waitForExpectations(timeout: 10)
            XCTAssertTrue(scene.exists)
            identities.append(scene.identifier)
            XCTAssertEqual(app.state, .runningForeground)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "native-navigation-\(button)"; shot.lifetime = .keepAlways; add(shot)
        }
        XCTAssertEqual(Set(identities.prefix(4)).count, 4)
        XCTAssertEqual(identities[4], identities[2])
        let trace = XCTAttachment(string: identities.map {
            "[native-probe] focus=" + $0.replacingOccurrences(of: "swift-presentation-home-", with: "")
        }.joined(separator: "\n"))
        trace.name = "native-navigation-focus-trace"; trace.lifetime = .keepAlways; add(trace)
        app.terminate()
    }

    func testHomeScrollingPerformanceWorkload() {
        let app = XCUIApplication(bundleIdentifier: "cc.dexworld.dexlegacy")
        app.launchEnvironment = ["NUVIO_UI_PREVIEW": "1", "NUVIO_UI_PREVIEW_POSTER_ROWS": "1",
                                 "NUVIO_SWIFT_SCENE": "1", "NUVIO_NATIVE_UI": "1",
                                 "NUVIO_SCENE_PERF": "1", "NUVIO_NATIVE_UI_STATS": "1"]
        app.launch()
        let scene = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@",
            "swift-presentation-home-native-control-")).firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 5)
        XCUIRemote.shared.press(.down)
        for _ in 0..<3 {
            for _ in 0..<5 { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.2) }
            for _ in 0..<5 { XCUIRemote.shared.press(.left); Thread.sleep(forTimeInterval: 0.2) }
            XCUIRemote.shared.press(.down); XCUIRemote.shared.press(.up)
        }
        XCTAssertEqual(app.state, .runningForeground)
        Thread.sleep(forTimeInterval: 5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "performance-home-final"; shot.lifetime = .keepAlways; add(shot)
        app.terminate()
    }
    private func launchPerformanceBuild(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "cc.dexworld.dexlegacy")
        // Leave NUVIO_SWIFT_SCENE unset to exercise the shipping default.
        app.launchEnvironment = ["NUVIO_UI_PREVIEW": "1", "NUVIO_UI_PREVIEW_SCREEN": screen,
                                 "NUVIO_UI_PREVIEW_POSTER_ROWS": "1", "NUVIO_NATIVE_UI_STATS": "1"]
        app.launch()
        return app
    }
    func testPerformanceBuildKeepsNativeFocusAcrossRows() {
        let app = launchPerformanceBuild("home")
        let probe = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@",
            "native-presentation-home-native-control-")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 30))
        var identities = [probe.identifier]
        for button in [XCUIRemote.Button.down, .right, .down, .up] {
            let before = probe.identifier
            XCUIRemote.shared.press(button)
            expectation(for: NSPredicate(format: "identifier != %@", before), evaluatedWith: probe)
            waitForExpectations(timeout: 15)
            identities.append(probe.identifier)
        }
        XCTAssertEqual(Set(identities.prefix(4)).count, 4)
        XCTAssertEqual(identities[4], identities[2])
        let trace = XCTAttachment(string: identities.map {
            "[native-probe] focus=" + $0.replacingOccurrences(of: "native-presentation-home-", with: "")
        }.joined(separator: "\n"))
        trace.name = "native-navigation-focus-trace"; trace.lifetime = .keepAlways; add(trace)
        app.terminate()
    }
    func testPerformanceBuildPresentsOriginalScreens() {
        let screens = [("home", "home"), ("detail", "detalhe"), ("search", "busca"),
                       ("library", "biblioteca"), ("settings", "ajustes"), ("menu", "menu"),
                       ("explore", "explorar"), ("guide", "guia"), ("profile", "perfil"),
                       ("addons", "addons"), ("plugins", "plugins"), ("agenda", "agenda")]
        for (route, name) in screens {
            let app = launchPerformanceBuild(route)
            let probe = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@",
                "native-presentation-" + name + "-")).firstMatch
            XCTAssertTrue(probe.waitForExistence(timeout: 30), route)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "performance-application-" + route; shot.lifetime = .keepAlways; add(shot)
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }

}
