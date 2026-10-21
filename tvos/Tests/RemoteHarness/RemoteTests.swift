import XCTest

final class RemoteInputTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["NUVIO_SWIFT_SCENE"] = "0"
        app.launch()
        let receiver = app.staticTexts["focus-receiver"]
        XCTAssertTrue(receiver.waitForExistence(timeout: 10))
        let ready = NSPredicate(format: "value == %@", "NvRemoteView")
        expectation(for: ready, evaluatedWith: receiver)
        waitForExpectations(timeout: 10)
    }
    private func counts() throws -> [String: Int] {
        let value = try XCTUnwrap(app.staticTexts["events"].value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Int])
    }
    func testAllFourDirectionsMoveExactlyOnce() throws {
        let remote = XCUIRemote.shared
        for direction in [XCUIRemote.Button.up, .down, .left, .right] { remote.press(direction) }
        let result = try counts()
        for direction in ["up", "down", "left", "right"] { XCTAssertEqual(result[direction], 1) }
        XCTAssertEqual(result["arrowUps"], 4)
    }
    func testQuickSeparateClicksAreNotThrottled() throws {
        for _ in 0..<8 { XCUIRemote.shared.press(.right) }
        XCTAssertEqual(try counts()["right"], 8)
        XCTAssertEqual(try counts()["arrowUps"], 8)
    }
    func testHeldDirectionStopsOnRelease() throws {
        XCUIRemote.shared.press(.down, forDuration: 1.0)
        let stopped = try counts()
        XCTAssertTrue((4...7).contains(stopped["down"] ?? 0))
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(try counts(), stopped, "No trailing navigation after lifting the button")
    }
    func testSystemDialogOwnsDirectionsAndRestoresFocusWithoutMoving() throws {
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.alerts["System dialog"].waitForExistence(timeout: 5))
        let before = try counts()
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.down)
        XCTAssertEqual(try counts(), before)
        XCUIRemote.shared.press(.select)
        expectation(for: NSPredicate(format: "value == %@", "NvRemoteView"), evaluatedWith: app.staticTexts["focus-receiver"])
        waitForExpectations(timeout: 5)
        XCTAssertEqual(try counts(), before)
        XCUIRemote.shared.press(.up)
        XCTAssertEqual(try counts()["up"], 1)
    }
    func testSelectAndPlayPauseKeepTheirButtonEvents() throws {
        XCUIRemote.shared.press(.select, forDuration: 0.6)
        XCUIRemote.shared.press(.playPause)
        let result = try counts()
        XCTAssertEqual(result["select"], 1)
        XCTAssertEqual(result["selectUp"], 1)
        XCTAssertEqual(result["pause"], 1)
        XCTAssertEqual(result["arrowUps"], 0)
    }
}
