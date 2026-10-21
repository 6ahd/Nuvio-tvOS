import UIKit

private var seededSwiftScene = false
private var readbackResult: Int32 = 0
@_cdecl("nv_test_swift_readback")
func nvTestSwiftReadback() -> Int32 { readbackResult }
private func primitive(_ mode: Int32, _ rect: CGRect, _ color: NvSceneColor = NvSceneColor(r: 1, g: 1, b: 1, a: 1)) -> NvSceneCommand {
    var c = NvSceneCommand()
    c.mode = mode; c.rect = NvSceneRect(x: Float(rect.minX), y: Float(rect.minY), w: Float(rect.width), h: Float(rect.height))
    c.color = color; c.background = NvSceneColor(r: 0, g: 0, b: 0, a: 1)
    c.uv = NvSceneRect(x: 0, y: 0, w: 1, h: 1)
    c.grad0 = NvSceneColor(r: 1, g: 0, b: 0, a: 1)
    c.grad1 = NvSceneColor(r: 0, g: 1, b: 0, a: 1)
    c.grad2 = NvSceneColor(r: 0, g: 0, b: 1, a: 1)
    return c
}
@_cdecl("nv_test_swift_frame")
func nvTestSwiftFrame(_ selection: Int32) {
    if !seededSwiftScene {
        seededSwiftScene = true
        var pixels = [UInt8](repeating: 0, count: 64 * 96 * 4)
        for y in 0..<96 { for x in 0..<64 {
            let p = (y * 64 + x) * 4
            pixels[p] = y < 48 ? 255 : 0; pixels[p+2] = y < 48 ? 0 : 255; pixels[p+3] = y < 48 ? 0 : 255
        } }
        pixels.withUnsafeBytes { nvSceneTexture(7001, 0, 0, 0, 64, 96, 0x1908, 4, $0.baseAddress, 1) }
        "سويفت Swift".withCString { text in
            "System".withCString { family in "Regular".withCString { face in
                nvSceneText(7002, text, family, face, 44, 46, 55, 0, 1, 1, 1, 1, 0)
            } }
        }
        // RGB data with a padded row checks GL_UNPACK_ALIGNMENT handling.
        let rgb: [UInt8] = [0,255,0, 0,255,0, 0,0, 0,0,255, 0,0,255, 0,0]
        rgb.withUnsafeBytes { nvSceneTexture(7004, 0, 0, 0, 2, 2, 0x1907, 4, $0.baseAddress, 1) }
        // The image decoder can upload a large image over several frames.
        nvSceneTexture(7005, 0, 0, 0, 2, 2, 0x1908, 4, nil, 1)
        let top: [UInt8] = [255,0,0,255, 255,0,0,255]
        let bottom: [UInt8] = [0,0,255,255, 0,0,255,255]
        top.withUnsafeBytes { nvSceneTexture(7005, 0, 0, 0, 2, 1, 0x1908, 4, $0.baseAddress, 0) }
        bottom.withUnsafeBytes { nvSceneTexture(7005, 0, 0, 1, 2, 1, 0x1908, 4, $0.baseAddress, 0) }
        let checker: [UInt8] = [255,255,255,255, 0,0,0,255, 0,0,0,255, 255,255,255,255]
        checker.withUnsafeBytes { nvSceneTexture(7006, 0, 0, 0, 2, 2, 0x1908, 4, $0.baseAddress, 1) }
        nvSceneTextureFilter(7006, 0x2801, 0x2600); nvSceneTextureFilter(7006, 0x2800, 0x2600)
    }
    let screens = ["home", "detail", "search", "library", "settings", "profiles", "guide", "addons", "social", "player"]
    NvSwiftScene.shared.begin(screen: screens[Int(selection) % screens.count], background: .black)
    let scene = NvSwiftScene.shared
    if ProcessInfo.processInfo.arguments.contains("--all-modes") {
        for mode in 0..<54 {
            var c = primitive(Int32(mode), CGRect(x: 200 + mode % 9 * 175, y: 450 + mode / 9 * 110, width: 150, height: 90))
            c.texture = 7001; c.radius = 0.1; c.focus = 0.5; c.parx = 0.2; c.pary = 0.4
            scene.draw(c)
        }
    } else {
        scene.draw(primitive(2, CGRect(x: 160, y: 720, width: 240, height: 220), NvSceneColor(r: 1, g: 0, b: 0, a: 1)))
        var hole = primitive(2, CGRect(x: 160, y: 720, width: 80, height: 80), NvSceneColor(r: 0, g: 0, b: 0, a: 0))
        hole.flags = 32; scene.draw(hole)
        var poster = primitive(0, CGRect(x: 1460, y: 600, width: 240, height: 360))
        poster.texture = 7001; poster.aspect = 2.0/3; poster.radius = 0.05
        scene.draw(poster)
        var text = primitive(5, CGRect(x: 600, y: 700, width: 650, height: 55)); text.texture = 7002
        scene.draw(text)
        var clipped = primitive(2, CGRect(x: 600, y: 820, width: 400, height: 100), NvSceneColor(r: 0, g: 1, b: 0, a: 1))
        clipped.flags = 1; clipped.clip = NvSceneRect(x: 650, y: 840, w: 100, h: 50)
        scene.draw(clipped)
        var checker = primitive(8, CGRect(x: 1050, y: 600, width: 120, height: 120)); checker.texture = 7006
        scene.draw(checker)
        var hero = primitive(37, CGRect(x: 1720, y: 800, width: 160, height: 160), NvSceneColor(r: 0, g: 0, b: 0, a: 0))
        hero.texture = 7001; hero.texture2 = 7005; hero.flags = 64; hero.aspect = 2.0/3; hero.aspect2 = 1; hero.alpha2 = 1
        scene.draw(hero)
        for (id, x) in [(UInt32(7004), 1050), (UInt32(7005), 1250)] {
            var image = primitive(25, CGRect(x: x, y: 800, width: 120, height: 120)); image.texture = id
            scene.draw(image)
        }
        // Exercise a native render target, reused by scene thumbnails.
        nvSceneTexture(7010, 0, 0, 0, 64, 64, 0x1908, 4, nil, 1)
        scene.bind(framebuffer: 901); scene.attach(framebuffer: 901, texture: 7010)
        scene.clear(color: .blue, clipped: false, pixelRect: .zero, viewport: CGSize(width: 64, height: 64))
        scene.draw(primitive(2, CGRect(x: 0, y: 0, width: 960, height: 1080), NvSceneColor(r: 1, g: 1, b: 1, a: 1)))
        nvSceneTexture(7011, 0, 0, 0, 64, 64, 0x1908, 4, nil, 1)
        scene.attach(framebuffer: 901, texture: 7011)
        scene.clear(color: .red, clipped: false, pixelRect: .zero, viewport: CGSize(width: 64, height: 64))
        scene.attach(framebuffer: 901, texture: 7010)
        scene.bind(framebuffer: 0)
        var snapshot = primitive(8, CGRect(x: 420, y: 800, width: 120, height: 120)); snapshot.texture = 7010
        scene.draw(snapshot)
        snapshot.rect.x = 570; snapshot.texture = 7011; scene.draw(snapshot)
        // Poster edge veils are anchored to screen coordinates, including
        // cards above and below their ramps; native layers must retain them.
        for rect in [CGRect(x: 1820, y: 160, width: 80, height: 200),
                     CGRect(x: 20, y: 700, width: 100, height: 360)] {
            var edge = primitive(0, rect)
            edge.texture = 7001; edge.aspect = 2.0/3; edge.flags = 4; edge.focus = 1
            scene.draw(edge)
        }
    }
    scene.end()
    if readbackResult == 0 {
        var rgb = [UInt8](repeating: 0, count: 3)
        let success = rgb.withUnsafeMutableBytes {
            nvSceneReadPixels(1580, 1080 - 660 - 1, 1, 1, 0x1907, 4, 1920, 1080, $0.baseAddress)
        }
        if success != 0 { readbackResult = Int32(rgb[0]) << 16 | Int32(rgb[1]) << 8 | Int32(rgb[2]) }
    }
}
