import XCTest
import UIKit

final class NativeUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["NUVIO_SWIFT_SCENE"] = "0"
        app.launchArguments = ["--native-fixture"]
        app.launch()
        let receiver = app.staticTexts["focus-receiver"]
        XCTAssertTrue(receiver.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "NvNativeControl"), evaluatedWith: receiver)
        waitForExpectations(timeout: 10)
    }
    private func counts() throws -> [String: Int] {
        let value = try XCTUnwrap(app.staticTexts["events"].value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Int])
    }
    func testNativeFocusMovesAcrossPostersWithoutSDLArrows() throws {
        XCUIRemote.shared.press(.right)
        XCTAssertEqual(try counts()["column"], 1)
        XCUIRemote.shared.press(.down)
        XCTAssertEqual(try counts()["row"], 1)
        XCUIRemote.shared.press(.up)
        XCTAssertEqual(try counts()["row"], 0)
        XCUIRemote.shared.press(.left)
        XCTAssertEqual(try counts()["column"], 0)
        let result = try counts()
        for key in ["up", "down", "left", "right", "arrowUps"] {
            XCTAssertEqual(result[key], 0, "Unexpected fallback \(key): \(result)")
        }
    }
    func testOffscreenPostersAndRowsRemainReachable() throws {
        for _ in 0..<8 { XCUIRemote.shared.press(.right) }
        XCTAssertEqual(try counts()["column"], 8)
        for _ in 0..<5 { XCUIRemote.shared.press(.down) }
        XCTAssertEqual(try counts()["row"], 5)
        XCUIRemote.shared.press(.up)
        XCTAssertEqual(try counts()["row"], 4)
    }
    func testNativePosterUsesDecodedPixelsWithCorrectChannels() throws {
        try assertNativePosterPixels()
    }
    func testTrailerPlaneCannotCoverNativePosters() throws {
        app.terminate()
        app.launchArguments = ["--native-fixture", "--video-plane"]
        app.launch()
        expectation(for: NSPredicate(format: "value CONTAINS %@", "NvNativeControl"), evaluatedWith: app.staticTexts["focus-receiver"])
        waitForExpectations(timeout: 10)
        try assertNativePosterPixels()
    }
    private func assertNativePosterPixels() throws {
        XCTAssertEqual(try counts()["nativePoster"], 1)
        let screenshot = try XCTUnwrap(app.screenshot().image.cgImage)
        let width = screenshot.width, height = screenshot.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(screenshot, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let offset = ((y * height / 1080) * width + x * width / 1920) * 4
            return Array(pixels[offset..<offset + 4])
        }
        let red = pixel(1720, 220), blue = pixel(1720, 460)
        XCTAssertGreaterThan(red[0], 150, "red top: \(red)")
        XCTAssertLessThan(red[2], 30)
        XCTAssertGreaterThan(blue[2], 150, "blue bottom: \(blue)")
        XCTAssertLessThan(blue[0], 30)
    }
    func testUnmarkedScreensKeepLegacySelectionAndInput() throws {
        app.terminate()
        app.launchArguments = ["--native-fixture", "--unmarked-focus"]
        app.launch()
        let receiver = app.staticTexts["focus-receiver"]
        expectation(for: NSPredicate(format: "value == %@", "NvRemoteView"), evaluatedWith: receiver)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(try counts()["row"], 0)
        XCTAssertEqual(try counts()["column"], 0)
        XCUIRemote.shared.press(.down)
        XCTAssertEqual(try counts()["row"], 1)
        XCTAssertEqual(try counts()["down"], 1)
    }
    func testNativeSelectKeepsLongPressAndRestoresAfterSystemDialog() throws {
        XCUIRemote.shared.press(.select, forDuration: 0.7)
        XCTAssertEqual(try counts()["select"], 1)
        XCTAssertEqual(try counts()["selectUp"], 1)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.alerts["System dialog"].waitForExistence(timeout: 5))
        let before = try counts()
        XCUIRemote.shared.press(.down)
        XCTAssertEqual(try counts(), before)
        XCUIRemote.shared.press(.select)
        expectation(for: NSPredicate(format: "value CONTAINS %@", "NvNativeControl"), evaluatedWith: app.staticTexts["focus-receiver"])
        waitForExpectations(timeout: 5)
        XCTAssertEqual(try counts()["select"], before["select"])
        XCTAssertEqual(try counts()["selectUp"], before["selectUp"])
    }
}
