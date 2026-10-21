import UIKit
import CoreText
import CoreImage

struct NvSceneText: Equatable {
    let text: String
    let family: String
    let face: String
    let size: CGFloat
    let ascent: CGFloat
    let lineHeight: CGFloat
    let tracking: CGFloat
    let color: UIColor
    let emphasis: Int
}

// Texture IDs are resource identities, never pointers into a C surface. Pixel
// storage is copied before the C decoder frees/reuses it. Partial uploads are
// assembled before making a new immutable CGImage.
final class NvSceneResources {
    static let shared = NvSceneResources()
    private struct Pixels {
        var data: Data
        let width: Int
        let height: Int
        var image: UIImage?
        var opaque: UIImage?
    }
    private var pixels: [UInt32: Pixels] = [:]
    private var aliases: [UInt32: (UInt32, CGFloat)] = [:]
    private var snapshots: [UInt32: UIImage] = [:]
    private(set) var texts: [UInt32: NvSceneText] = [:]
    private(set) var revision: UInt64 = 0
    private var generations: [UInt32: UInt64] = [:]
    private func changed(_ id: UInt32) { revision &+= 1; generations[id] = revision }
    func generation(_ id: UInt32, visited: Set<UInt32> = []) -> UInt64 {
        guard id != 0, !visited.contains(id) else { return 0 }
        let own = generations[id] ?? 0
        if let alias = aliases[id] { return own &* 31 &+ generation(alias.0, visited: visited.union([id])) }
        return own
    }
    private let filtered = NSCache<NSString, UIImage>()
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private var registered = false
    private var samplers: [UInt32: [Int32: Int32]] = [:]
    private var fontNames: [String: String] = [:]

    private init() {
        filtered.totalCostLimit = 24 * 1024 * 1024
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.filtered.removeAllObjects()
            // Live textures and snapshots cannot be dropped: the core still
            // owns them and would not request their pixels again.
        }
    }

    func remove(_ id: UInt32, scene: Bool = true, sampler: Bool = false) {
        guard id != 0 else { return }
        pixels.removeValue(forKey: id)
        aliases.removeValue(forKey: id)
        snapshots.removeValue(forKey: id)
        texts.removeValue(forKey: id)
        pendingSizes.removeValue(forKey: id)
        if scene { NvSwiftScene.shared.remove(id) }
        if sampler { samplers.removeValue(forKey: id) }
        changed(id)
        if sampler { generations.removeValue(forKey: id) }
    }

    func upload(_ id: UInt32, x: Int, y: Int, width: Int, height: Int,
                format: Int, alignment: Int, bytes: UnsafeRawPointer?, replace: Bool) {
        guard id != 0, width > 0, height > 0, width <= 8192, height <= 8192,
              [1, 2, 4, 8].contains(alignment) else { return }
        if replace { remove(id) }
        if replace { NvSwiftScene.shared.size(id, width: width, height: height) }
        // A nil allocation is an FBO or the beginning of a striped upload.
        // Allocate its CPU buffer only when an actual stripe arrives.
        guard let bytes else {
            if replace { pendingSizes[id] = (width, height) }
            return
        }
        let channels = format == 0x1907 ? 3 : format == 0x1908 ? 4 : 1
        guard [0x1906, 0x1907, 0x1908, 0x1909].contains(format) else { return }
        let total = replace ? (width, height) : pixels[id].map { ($0.width, $0.height) } ?? pendingSizes[id]
        guard let total, x >= 0, y >= 0, x + width <= total.0, y + height <= total.1,
              total.0 * total.1 <= 16_777_216 else { return }
        let rowBytes = ((width * channels + alignment - 1) / alignment) * alignment
        var slot = pixels[id] ?? Pixels(data: Data(count: total.0 * total.1 * 4),
                                        width: total.0, height: total.1)
        slot.data.withUnsafeMutableBytes { destination in
            guard let out = destination.bindMemory(to: UInt8.self).baseAddress else { return }
            let source = bytes.assumingMemoryBound(to: UInt8.self)
            for row in 0..<height {
                let from = source + row * rowBytes
                let to = out + ((y + row) * total.0 + x) * 4
                if channels == 4 { memcpy(to, from, width * 4); continue }
                for column in 0..<width {
                    let i = column * 4
                    if channels == 3 {
                        to[i] = from[column * 3]; to[i+1] = from[column * 3+1]; to[i+2] = from[column * 3+2]
                        to[i+3] = 255
                    } else if format == 0x1906 {
                        to[i] = 255; to[i+1] = 255; to[i+2] = 255; to[i+3] = from[column]
                    } else {
                        to[i] = from[column]; to[i+1] = from[column]; to[i+2] = from[column]; to[i+3] = 255
                    }
                }
            }
        }
        slot.image = nil; slot.opaque = nil
        pixels[id] = slot
        aliases.removeValue(forKey: id)
        snapshots.removeValue(forKey: id)
        pendingSizes.removeValue(forKey: id)
        changed(id)
    }
    private var pendingSizes: [UInt32: (Int, Int)] = [:]

    func filter(_ id: UInt32, property: Int32, value: Int32) {
        guard id != 0, samplers[id]?[property] != value else { return }
        samplers[id, default: [:]][property] = value
        changed(id)
    }
    func sampling(_ id: UInt32) -> (CALayerContentsFilter, CALayerContentsFilter) {
        let min = samplers[id]?[0x2801] ?? 0x2703, mag = samplers[id]?[0x2800] ?? 0x2601
        return (min == 0x2600 || min == 0x2700 ? .nearest : min == 0x2703 ? .trilinear : .linear,
                mag == 0x2600 ? .nearest : .linear)
    }

    func defineText(_ id: UInt32, _ text: NvSceneText) {
        remove(id)
        pendingSizes.removeValue(forKey: id)
        texts[id] = text
        changed(id)
    }
    func snapshot(_ id: UInt32, _ image: UIImage) {
        remove(id, scene: false)
        snapshots[id] = image
        changed(id)
    }
    func alias(_ id: UInt32, source: UInt32, blur: CGFloat) {
        guard id != 0, id != source else { return }
        aliases[id] = (source, blur)
        changed(id)
    }

    func image(_ id: UInt32, opaque: Bool = false, blur: CGFloat = 0,
               visited: Set<UInt32> = []) -> UIImage? {
        guard id != 0, !visited.contains(id) else { return nil }
        if let (source, amount) = aliases[id] {
            return image(source, opaque: opaque, blur: max(blur, amount), visited: visited.union([id]))
        }
        var image = snapshots[id]
        if image == nil, var slot = pixels[id] {
            image = opaque ? slot.opaque : slot.image
            if image == nil, let provider = CGDataProvider(data: slot.data as CFData),
               let cg = CGImage(width: slot.width, height: slot.height, bitsPerComponent: 8,
                                bitsPerPixel: 32, bytesPerRow: slot.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: (opaque ? CGImageAlphaInfo.noneSkipLast : .last).rawValue)
                                    .union(.byteOrder32Big), provider: provider, decode: nil,
                                shouldInterpolate: true, intent: .defaultIntent) {
                image = UIImage(cgImage: cg)
                if opaque { slot.opaque = image } else { slot.image = image }
                pixels[id] = slot
            }
        }
        guard blur > 0, let image, let cg = image.cgImage else { return image }
        let key = "\(id):\(generation(id)):\(opaque):\(Int(blur * 4))" as NSString
        if let cached = filtered.object(forKey: key) { return cached }
        let source = CIImage(cgImage: cg)
        let result = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
        guard let output = ci.createCGImage(result, from: source.extent) else { return image }
        let filteredImage = UIImage(cgImage: output)
        filtered.setObject(filteredImage, forKey: key, cost: output.width * output.height * 4)
        return filteredImage
    }

    func font(for text: NvSceneText) -> UIFont {
        registerFonts()
        let key = normalize(text.family + " " + text.face)
        let family = normalize(text.family)
        let exact = fontNames[key] ?? fontNames[family]
        var font = exact.flatMap { UIFont(name: $0, size: text.size) }
            ?? UIFont(name: text.family, size: text.size)
            ?? UIFont.systemFont(ofSize: text.size,
                                 weight: text.face.lowercased().contains("bold") ? .bold : .regular)
        var traits = font.fontDescriptor.symbolicTraits
        if text.emphasis & 1 != 0 { traits.insert(.traitBold) }
        if text.emphasis & 2 != 0 { traits.insert(.traitItalic) }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: descriptor, size: text.size)
        }
        return font
    }
    private func normalize(_ string: String) -> String {
        string.lowercased().filter { $0.isLetter || $0.isNumber }
    }
    private func registerFonts() {
        guard !registered else { return }
        registered = true
        guard let base = Bundle.main.resourceURL,
              let iterator = FileManager.default.enumerator(at: base.appendingPathComponent("fonts"),
                                                             includingPropertiesForKeys: nil) else { return }
        for case let url as URL in iterator where ["ttf", "otf", "ttc"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { continue }
            for descriptor in descriptors {
                let font = CTFontCreateWithFontDescriptor(descriptor, 20, nil)
                let family = CTFontCopyFamilyName(font) as String
                let face = CTFontCopyName(font, kCTFontSubFamilyNameKey) as String? ?? "Regular"
                let name = CTFontCopyPostScriptName(font) as String
                fontNames[normalize(family + " " + face)] = name
                if fontNames[normalize(family)] == nil || face.lowercased() == "regular" {
                    fontNames[normalize(family)] = name
                }
            }
        }
    }
}

@_cdecl("nvscene_texture")
func nvSceneTexture(_ id: UInt32, _ level: Int32, _ x: Int32, _ y: Int32,
                    _ width: Int32, _ height: Int32, _ format: Int32,
                    _ alignment: Int32, _ bytes: UnsafeRawPointer?, _ replace: Int32) {
    guard NvSwiftScene.enabled, level == 0 else { return }
    NvSceneResources.shared.upload(id, x: Int(x), y: Int(y), width: Int(width), height: Int(height),
                                   format: Int(format), alignment: Int(alignment), bytes: bytes, replace: replace != 0)
}
@_cdecl("nvscene_texture_delete")
func nvSceneTextureDelete(_ id: UInt32) { NvSceneResources.shared.remove(id, sampler: true) }
@_cdecl("nvscene_texture_filter")
func nvSceneTextureFilter(_ id: UInt32, _ property: Int32, _ value: Int32) {
    guard NvSwiftScene.enabled else { return }
    NvSceneResources.shared.filter(id, property: property, value: value)
}
@_cdecl("nvscene_alias")
func nvSceneAlias(_ id: UInt32, _ source: UInt32, _ blur: Float) {
    guard NvSwiftScene.enabled else { return }
    NvSceneResources.shared.alias(id, source: source, blur: CGFloat(blur))
}
@_cdecl("nvscene_text")
func nvSceneText(_ id: UInt32, _ text: UnsafePointer<CChar>?, _ family: UnsafePointer<CChar>?,
                 _ face: UnsafePointer<CChar>?, _ size: Float, _ ascent: Float, _ lineHeight: Float, _ tracking: Float,
                 _ red: Float, _ green: Float, _ blue: Float, _ alpha: Float, _ emphasis: Int32) {
    guard NvSwiftScene.enabled, let text, size > 0 else { return }
    NvSceneResources.shared.defineText(id, NvSceneText(text: String(cString: text),
        family: family.map(String.init(cString:)) ?? "Inter Display", face: face.map(String.init(cString:)) ?? "Regular",
        size: CGFloat(size), ascent: CGFloat(ascent), lineHeight: CGFloat(lineHeight), tracking: CGFloat(tracking),
        color: UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha)),
        emphasis: Int(emphasis)))
}
