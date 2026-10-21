import XCTest
import UIKit

final class SwiftSceneTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["NUVIO_SWIFT_SCENE"] = "1"
        app.launchArguments = ["--native-fixture", "--swift-scene", "--video-plane"]
        app.launch()
        XCTAssertTrue(app.otherElements["swift-presentation-home"].waitForExistence(timeout: 10))
    }
    private func pixels() throws -> (Int, Int, [UInt8]) {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { data in
            let c = try XCTUnwrap(CGContext(data: data.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (image.width, image.height, bytes)
    }
    private func sample(_ image: (Int, Int, [UInt8]), _ x: Int, _ y: Int) -> [UInt8] {
        let offset = ((y * image.1 / 1080) * image.0 + x * image.0 / 1920) * 4
        return Array(image.2[offset..<offset+4])
    }
    func testNativeTextPreservesLogicalArabicAndLatin() {
        XCTAssertTrue(app.staticTexts["سويفت Swift"].waitForExistence(timeout: 5))
    }
    func testSwiftPosterIgnoresSourceAlphaLikeOriginalRGBCard() throws {
        let image = try pixels(), red = sample(image, 1580, 660), blue = sample(image, 1580, 900)
        XCTAssertGreaterThan(red[0], 150); XCTAssertLessThan(red[2], 30)
        XCTAssertGreaterThan(blue[2], 150); XCTAssertLessThan(blue[0], 30)
    }
    func testPosterScreenVeilsKeepOriginalGradientAndCoordinateSpace() throws {
        let image = try pixels()
        let top = sample(image, 1860, 200), middle = sample(image, 1860, 340)
        XCTAssertGreaterThan(top[0], 145); XCTAssertLessThan(top[0], 180)
        XCTAssertGreaterThan(middle[2], 235)
        let lowerTop = sample(image, 60, 800), lowerBottom = sample(image, 60, 1020)
        XCTAssertGreaterThan(lowerTop[0], 220)
        XCTAssertGreaterThan(lowerBottom[2], 45); XCTAssertLessThan(lowerBottom[2], 80)
    }
    func testVideoHoleClearsOnlyEarlierLayersAndClippingKeepsGeometry() throws {
        let image = try pixels(), video = sample(image, 200, 760), red = sample(image, 300, 850)
        XCTAssertGreaterThan(video[1], 200); XCTAssertLessThan(video[0], 30)
        XCTAssertGreaterThan(red[0], 200); XCTAssertLessThan(red[1], 30)
        XCTAssertGreaterThan(sample(image, 700, 860)[1], 200)
        XCTAssertLessThan(sample(image, 800, 860)[1], 30)
    }
    func testPaddedRGBRowsAndPartialUploadsKeepTheirPixels() throws {
        let image = try pixels()
        XCTAssertGreaterThan(sample(image, 1110, 820)[1], 200)
        XCTAssertGreaterThan(sample(image, 1110, 900)[2], 200)
        XCTAssertGreaterThan(sample(image, 1310, 820)[0], 200)
        XCTAssertGreaterThan(sample(image, 1310, 900)[2], 200)
    }
    func testNativeSnapshotHasCorrectOrientationAndContents() throws {
        let image = try pixels()
        let white = sample(image, 440, 850), blue = sample(image, 520, 850)
        XCTAssertGreaterThan(white[0], 200); XCTAssertGreaterThan(white[1], 200)
        XCTAssertLessThan(blue[0], 30); XCTAssertGreaterThan(blue[2], 200)
        let replacedAttachment = sample(image, 620, 850)
        XCTAssertGreaterThan(replacedAttachment[0], 200)
        XCTAssertLessThan(replacedAttachment[2], 30)
    }
    func testQRCodeSamplingPreservesHardModuleEdges() throws {
        let image = try pixels()
        XCTAssertGreaterThan(sample(image, 1107, 620)[0], 245)
        XCTAssertLessThan(sample(image, 1112, 620)[0], 10)
    }
    func testHeroCrossfadeKeepsPreviousArtWhenNextArtStartsTransparent() throws {
        let image = try pixels()
        XCTAssertGreaterThan(sample(image, 1840, 830)[0], 200)
        XCTAssertGreaterThan(sample(image, 1840, 920)[2], 180)
    }
    func testLegacyReadbackSeesNativePixelsInBottomLeftCoordinates() throws {
        let value = try XCTUnwrap(app.staticTexts["events"].value as? String)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Int])
        let rgb = try XCTUnwrap(result["nativeReadback"])
        XCTAssertGreaterThan((rgb >> 16) & 255, 150)
        XCTAssertLessThan(rgb & 255, 30)
    }
    func testCustomNativeActionsNeverEmitDuplicateSDLSelect() throws {
        app.terminate(); app.launchArguments += ["--custom-action"]; app.launch()
        XCTAssertTrue(app.otherElements["swift-presentation-home"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.select)
        let value = try XCTUnwrap(app.staticTexts["events"].value as? String)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Int])
        XCTAssertEqual(result["customActivations"], 1)
        XCTAssertEqual(result["select"], 0); XCTAssertEqual(result["selectUp"], 0)
    }
    func testSceneChangesPreserveNativeRemoteAndSystemDialogs() {
        for name in ["detail", "search", "library", "settings", "profiles", "guide", "addons", "social", "player"] {
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.otherElements["swift-presentation-\(name)"].waitForExistence(timeout: 5))
        }
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.alerts["System dialog"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(app.alerts["System dialog"].exists)
    }
    func testEveryPresentationModeRendersAcrossRepeatedFrames() {
        app.terminate(); app.launchArguments += ["--all-modes"]; app.launch()
        XCTAssertTrue(app.otherElements["swift-presentation-home"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.down); XCUIRemote.shared.press(.up)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
