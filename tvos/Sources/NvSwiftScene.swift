import UIKit
import QuartzCore

// The shared core owns a synchronous SDL loop. When UIKit presents its scene,
// an almost-empty GL swap is not a reliable display clock. Yield to UIKit's
// run loop until the next display tick instead of submitting redundant frames
// and competing with focus/touch delivery. Never sleep the main thread.
private final class NvSceneClock: NSObject {
    static let shared = NvSceneClock()
    private var link: CADisplayLink!
    private var tick: UInt64 = 0
    private var consumed: UInt64 = 0
    private override init() {
        super.init()
        link = CADisplayLink(target: self, selector: #selector(advance))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
    }
    @objc private func advance() { tick &+= 1 }
    func wait() {
        guard Thread.isMainThread else { return }
        let deadline = Date(timeIntervalSinceNow: 0.05)
        while tick == consumed && deadline.timeIntervalSinceNow > 0 {
            RunLoop.main.run(mode: .default, before: deadline)
        }
        consumed = tick
    }
}

private enum NvSceneEvent {
    case primitive(NvSceneCommand)
    case hole(CGRect, CGFloat)
    case dissolve(CGFloat)
}

private struct NvSceneFrame {
    var events: [NvSceneEvent] = []
    var invalid = false
    mutating func append(_ event: NvSceneEvent) {
        guard events.count < 8192 else { invalid = true; return }
        events.append(event)
    }
}

// The owning controller now presents the whole scene: typography, artwork,
// ornaments, dialogs, profile choice, settings and playback overlays. The
// C-facing adapter supplies immutable presentation values and existing actions.
final class NvSwiftScene: UIViewController {
    static let shared = NvSwiftScene()
    // Whole-scene command translation is experimental. The shipping default
    // keeps the proven renderer with native Swift focus and poster surfaces.
    static let enabled = ProcessInfo.processInfo.environment["NUVIO_SWIFT_SCENE"] == "1"
    private let surface = NvSceneSurface()
    private var frame = NvSceneFrame()
    private var frameOpen = false
    private var target: UInt32 = 0
    private var boundFramebuffer: UInt32 = 0
    private var framebufferTextures: [UInt32: UInt32] = [:]
    private var targetFrames: [UInt32: NvSceneFrame] = [:]
    private var sizes: [UInt32: CGSize] = [:]
    private var targetSignatures: [UInt32: Data] = [:]
    private lazy var targetSurface = NvSceneSurface()
    private var temporaryTarget: [UInt32] = []
    private(set) var screen = ""
    private var frameNumber: UInt64 = 0
    private var previousSignature = Data()
    private weak var canvas: UIView?
    private static let measure = ProcessInfo.processInfo.environment["NUVIO_SCENE_PERF"] == "1"
    private var renderSamples: [Double] = []
    private var labelEventCount = -1
    private var labelEntries: [(CGRect, String, Int, Float)] = []
#if DEBUG
    private var lastFocusProbe = ""
#endif

    private init() { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() { view = surface }

    private func install() -> Bool {
        if canvas?.window == nil {
            func find(_ view: UIView) -> UIView? {
                if view.layer is CAEAGLLayer { return view }
                for child in view.subviews { if let result = find(child) { return result } }
                return nil
            }
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            guard let window = windows.first(where: { $0.isKeyWindow }),
                  let host = window.rootViewController, let canvas = find(host.view) else { return false }
            if parent !== host {
                willMove(toParent: nil); view.removeFromSuperview(); removeFromParent()
                host.addChild(self)
                canvas.insertSubview(view, at: 0)
                didMove(toParent: host)
            }
            self.canvas = canvas
            canvas.isOpaque = false; canvas.layer.isOpaque = false; canvas.backgroundColor = .clear
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.isUserInteractionEnabled = false
        }
        guard let canvas else { return false }
        if view.frame != canvas.bounds { view.frame = canvas.bounds }
#if DEBUG
        let tracingFocus = ProcessInfo.processInfo.environment["NUVIO_NATIVE_UI_STATS"] == "1"
#else
        let tracingFocus = false
#endif
        if !tracingFocus, view.accessibilityIdentifier != "swift-presentation-\(screen)" {
            view.accessibilityIdentifier = "swift-presentation-\(screen)"
        }
        view.isHidden = false
        return true
    }

    func begin(screen: String, background: UIColor) {
        self.screen = screen
        guard Self.enabled else { return }
        frameOpen = true; frame = NvSceneFrame(); target = 0
        labelEventCount = -1
        frameNumber &+= 1
        append(.primitive(Self.solid(CGRect(x: 0, y: 0, width: 1920, height: 1080), background)))
    }
    func draw(_ command: NvSceneCommand) {
        guard Self.enabled else { return }
        let rect = command.rect.cg
        let values = [rect.minX, rect.minY, rect.width, rect.height, CGFloat(command.color.a), CGFloat(command.radius)]
        guard values.allSatisfy(\.isFinite), rect.width > 0, rect.height > 0,
              rect.width < 1_000_000, rect.height < 1_000_000,
              (0..<54).contains(command.mode) else { return }
        if command.flags & 32 != 0 {
            let clipped = command.flags & 1 != 0 ? rect.intersection(command.clip.cg) : rect
            append(.hole(clipped, max(0, CGFloat(command.radius) * rect.height)))
            if command.color.a <= 0 { return }
        }
        append(.primitive(command))
    }
    private func append(_ event: NvSceneEvent) {
        if target != 0 {
            // Mutate the dictionary value in place; a local copy of its array
            // forced an allocation and copied every preceding draw command.
            targetFrames[target, default: NvSceneFrame()].append(event)
        } else if frameOpen { frame.append(event) }
    }
    func end() {
        guard Self.enabled, frameOpen else { return }
        let started = Self.measure ? CACurrentMediaTime() : 0
        flush(target)
        frameOpen = false
        guard !frame.invalid, install() else { return }
        let signature = Self.signature(frame)
        if signature != previousSignature {
            surface.render(frame)
            previousSignature = signature
        }
        if Self.measure {
            renderSamples.append((CACurrentMediaTime() - started) * 1000)
            if renderSamples.count == 240 {
                let sorted = renderSamples.sorted()
                print(String(format: "[scene-perf] frames=240 items=%d nodes=%d p50_ms=%.3f p95_ms=%.3f max_ms=%.3f", frame.events.count, surface.nodeCount, sorted[120], sorted[228], sorted[239]))
                renderSamples.removeAll(keepingCapacity: true)
            }
        }
#if DEBUG
        // SDL's child-controller accessibility hierarchy does not expose its
        // sibling focus controls to XCTest. Observe the real UIKit focus
        // system through the same scene that exposes the native labels.
        if ProcessInfo.processInfo.environment["NUVIO_NATIVE_UI_STATS"] == "1" {
            let focused = view.window?.windowScene?.focusSystem?.focusedItem as? UIView
            let value = focused?.accessibilityIdentifier ?? "none"
            if value != lastFocusProbe { print("[native-probe] focus=\(value)"); lastFocusProbe = value }
            view.accessibilityIdentifier = "swift-presentation-\(screen)-\(value)"
        }
#endif
        // Optional local diagnostics contain only aggregate counters, never
        // title names, URLs, login codes or account identifiers.
        if ProcessInfo.processInfo.environment["NUVIO_SWIFT_SCENE_STATS"] == "1", frameNumber % 300 == 0 {
            print("[swift-scene] frames=\(frameNumber) items=\(frame.events.count) nodes=\(surface.nodeCount)")
        }
    }

    func size(_ id: UInt32, width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        sizes[id] = CGSize(width: width, height: height)
    }
    func remove(_ id: UInt32) {
        sizes.removeValue(forKey: id); targetFrames.removeValue(forKey: id)
        targetSignatures.removeValue(forKey: id)
    }
    func attach(framebuffer: UInt32, texture: UInt32) {
        framebufferTextures[framebuffer] = texture == 0 ? nil : texture
        // Blur passes reuse a bound framebuffer and replace its attachment
        // without another bind. Finish the old target before switching.
        if framebuffer == boundFramebuffer { bind(framebuffer: framebuffer) }
    }
    func removeFramebuffer(_ id: UInt32) {
        if id == boundFramebuffer { bind(framebuffer: 0) }
        framebufferTextures.removeValue(forKey: id)
    }
    func bind(framebuffer: UInt32) {
        guard Self.enabled else { return }
        boundFramebuffer = framebuffer
        let next = framebufferTextures[framebuffer] ?? 0
        guard next != target else { return }
        flush(target)
        target = next
    }
    func targetBegin(_ id: UInt32, width: Int, height: Int, clear: Bool) {
        temporaryTarget.append(target)
        flush(target); target = id; size(id, width: width, height: height)
        if clear { targetFrames[id] = NvSceneFrame() }
    }
    func targetEnd() {
        flush(target)
        target = temporaryTarget.popLast() ?? 0
    }
    private func flush(_ id: UInt32) {
        guard id != 0, let frame = targetFrames[id], !frame.invalid,
              let size = sizes[id], size.width <= 8192, size.height <= 8192 else { return }
        let signature = Self.signature(frame)
        if targetSignatures[id] == signature { return }
        // One scratch hierarchy serves all snapshots. Keeping a hierarchy per
        // thumbnail would retain an unbounded set of decorative backing stores.
        let targetView = targetSurface
        targetView.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        targetView.render(frame)
        targetView.layoutIfNeeded()
        func display(_ layer: CALayer) { layer.displayIfNeeded(); layer.sublayers?.forEach(display) }
        display(targetView.layer)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.scaleBy(x: size.width / 1920, y: size.height / 1080)
            targetView.layer.render(in: context.cgContext)
        }
        NvSceneResources.shared.snapshot(id, image)
        targetSignatures[id] = signature
    }

    func clear(color: UIColor, clipped: Bool, pixelRect: CGRect, viewport: CGSize) {
        guard Self.enabled else { return }
        if !clipped {
            if target == 0 { frame = NvSceneFrame(); labelEventCount = -1 }
            else { targetFrames[target] = NvSceneFrame() }
            append(.primitive(Self.solid(CGRect(x: 0, y: 0, width: 1920, height: 1080), color)))
        } else {
            let size = target != 0 ? sizes[target] ?? viewport : viewport
            guard size.width > 0, size.height > 0 else { return }
            let rect = CGRect(x: pixelRect.minX / size.width * 1920,
                              y: (size.height - pixelRect.maxY) / size.height * 1080,
                              width: pixelRect.width / size.width * 1920,
                              height: pixelRect.height / size.height * 1080)
            append(.hole(rect, 0))
            if color.cgColor.alpha > 0 { append(.primitive(Self.solid(rect, color))) }
        }
    }
    func dissolve(_ alpha: CGFloat) { append(.dissolve(max(0, min(1, alpha)))) }

    func readPixels(x: Int, y: Int, width: Int, height: Int, format: Int, alignment: Int,
                    viewport: CGSize, destination: UnsafeMutableRawPointer) -> Bool {
        guard Self.enabled, Thread.isMainThread, width > 0, height > 0,
              width <= 8192, height <= 8192, width * height <= 16_777_216,
              [0x1907, 0x1908].contains(format), [1, 2, 4, 8].contains(alignment) else { return false }
        flush(target)
        if target != 0 && NvSceneResources.shared.image(target) == nil { return false }
        let sourceSize = target == 0 ? viewport : sizes[target] ?? viewport
        guard sourceSize.width > 0, sourceSize.height > 0, x >= 0, y >= 0,
              CGFloat(x + width) <= sourceSize.width, CGFloat(y + height) <= sourceSize.height else { return false }
        let top = sourceSize.height - CGFloat(y + height)
        let rendererFormat = UIGraphicsImageRendererFormat(); rendererFormat.scale = 1; rendererFormat.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: rendererFormat).image { context in
            context.cgContext.translateBy(x: -CGFloat(x), y: -top)
            if target != 0 {
                NvSceneResources.shared.image(target)?.draw(in: CGRect(origin: .zero, size: sourceSize))
            } else if frameOpen {
                let current = NvSceneSurface(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                current.render(frame); current.layoutIfNeeded()
                func display(_ layer: CALayer) { layer.displayIfNeeded(); layer.sublayers?.forEach(display) }
                display(current.layer)
                context.cgContext.scaleBy(x: sourceSize.width / 1920, y: sourceSize.height / 1080)
                current.layer.render(in: context.cgContext)
            } else {
                context.cgContext.scaleBy(x: sourceSize.width / max(1, surface.bounds.width),
                                          y: sourceSize.height / max(1, surface.bounds.height))
                surface.layer.render(in: context.cgContext)
            }
        }
        guard let cg = image.cgImage else { return false }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard rendered else { return false }
        let channels = format == 0x1907 ? 3 : 4
        let stride = ((width * channels + alignment - 1) / alignment) * alignment
        let output = destination.assumingMemoryBound(to: UInt8.self)
        // GL readback starts at the bottom row and follows GL_PACK_ALIGNMENT.
        for row in 0..<height { for column in 0..<width {
            let source = ((height - 1 - row) * width + column) * 4
            let target = row * stride + column * channels
            for channel in 0..<channels { output[target + channel] = rgba[source + channel] }
        } }
        return true
    }

    func label(in rect: CGRect) -> String? {
        guard Self.enabled, frameOpen else { return nil }
        if labelEventCount != frame.events.count {
            labelEntries.removeAll(keepingCapacity: true)
            for event in frame.events {
                guard case .primitive(let command) = event, command.mode == 5,
                      let text = NvSceneResources.shared.texts[command.texture]?.text else { continue }
                let length = text.count
                if length < 220 { labelEntries.append((command.rect.cg, text, length, command.color.a)) }
            }
            labelEventCount = frame.events.count
        }
        var found: [(CGRect, String)] = []
        for (box, text, _, alpha) in labelEntries where alpha > 0.4 {
            if rect.contains(CGPoint(x: box.midX, y: box.midY)) { found.append((box, text)) }
        }
        if found.isEmpty {
            // Portrait labels commonly sit just below the image hit rectangle.
            let caption = CGRect(x: rect.minX, y: rect.maxY, width: rect.width, height: 68)
            for (box, text, length, _) in labelEntries where length < 160 {
                if caption.contains(CGPoint(x: box.midX, y: box.midY)) { found.append((box, text)) }
            }
        }
        var seen = Set<String>()
        let strings = found.sorted { abs($0.0.minY - $1.0.minY) > 8 ? $0.0.minY < $1.0.minY : $0.0.minX < $1.0.minX }
            .compactMap { seen.insert($0.1).inserted ? $0.1 : nil }.prefix(6)
        return strings.isEmpty ? nil : strings.joined(separator: ", ")
    }

    private static func solid(_ rect: CGRect, _ color: UIColor) -> NvSceneCommand {
        var c = NvSceneCommand()
        c.mode = 2; c.rect = NvSceneRect(x: Float(rect.minX), y: Float(rect.minY), w: Float(rect.width), h: Float(rect.height))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        c.color = NvSceneColor(r: Float(r), g: Float(g), b: Float(b), a: Float(a))
        return c
    }
    private static func signature(_ frame: NvSceneFrame) -> Data {
        var result = Data(capacity: frame.events.count * MemoryLayout<NvSceneCommand>.size)
        for event in frame.events {
            switch event {
            case .primitive(var c):
                result.append(0); withUnsafeBytes(of: &c) { result.append(contentsOf: $0) }
                for id in [c.texture, c.texture2] {
                    var generation = NvSceneResources.shared.generation(id)
                    withUnsafeBytes(of: &generation) { result.append(contentsOf: $0) }
                }
            case .hole(var rect, var radius):
                result.append(1); withUnsafeBytes(of: &rect) { result.append(contentsOf: $0) }
                withUnsafeBytes(of: &radius) { result.append(contentsOf: $0) }
            case .dissolve(var alpha): result.append(2); withUnsafeBytes(of: &alpha) { result.append(contentsOf: $0) }
            }
        }
        return result
    }
}

private final class NvSceneSurface: UIView {
    private let design = UIView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    private var nodes: [NvScenePrimitive] = []
    private var groups: [UIView] = []
    var nodeCount: Int { nodes.count }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
        design.isUserInteractionEnabled = false; addSubview(design)
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        design.transform = .identity
        design.bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        design.center = CGPoint(x: bounds.midX, y: bounds.midY)
        design.transform = CGAffineTransform(scaleX: bounds.width / 1920, y: bounds.height / 1080)
    }
    func render(_ frame: NvSceneFrame) {
        UIView.performWithoutAnimation {
            // Retain the view hierarchy during scrolling. Only a real change
            // in composition reparents a view; moving its frame is enough.
            var used = 0, usedGroups = 0
            var children: [UIView] = []
            for event in frame.events {
                switch event {
                case .primitive(let command):
                    if used == nodes.count { nodes.append(NvScenePrimitive()) }
                    let node = nodes[used]; used += 1
                    node.update(command); children.append(node)
                case .hole(let rect, let radius):
                    guard !rect.isNull, !rect.isEmpty else { continue }
                    let group = group(at: usedGroups); usedGroups += 1
                    arrange(children, in: group)
                    let path = UIBezierPath(rect: design.bounds)
                    path.append(UIBezierPath(roundedRect: rect, cornerRadius: radius))
                    let mask = CAShapeLayer(); mask.path = path.cgPath; mask.fillRule = .evenOdd
                    group.layer.mask = mask
                    children = [group]
                case .dissolve(let alpha):
                    let group = group(at: usedGroups); usedGroups += 1
                    arrange(children, in: group); group.alpha = alpha
                    children = [group]
                }
            }
            arrange(children, in: design)
            // A screen switch should release old images/text views immediately.
            if nodes.count > used { nodes[used...].forEach { $0.removeFromSuperview() }; nodes.removeSubrange(used...) }
            if groups.count > usedGroups { groups[usedGroups...].forEach { $0.removeFromSuperview() }; groups.removeSubrange(usedGroups...) }
            layoutIfNeeded()
        }
    }
    private func group(at index: Int) -> UIView {
        if index == groups.count { groups.append(UIView(frame: design.bounds)) }
        let group = groups[index]
        group.frame = design.bounds; group.alpha = 1; group.layer.mask = nil
        group.isUserInteractionEnabled = false; group.backgroundColor = .clear
        return group
    }
    private func arrange(_ children: [UIView], in parent: UIView) {
        let existing = parent.subviews
        if existing.count == children.count && zip(existing, children).allSatisfy({ $0 === $1 }) { return }
        let identities = Set(children.map(ObjectIdentifier.init))
        for old in parent.subviews where !identities.contains(ObjectIdentifier(old)) { old.removeFromSuperview() }
        for (index, child) in children.enumerated() {
            if parent.isDescendant(of: child) { parent.removeFromSuperview() }
            if child.superview !== parent { parent.insertSubview(child, at: index) }
            else if parent.subviews[index] !== child { parent.insertSubview(child, at: index) }
        }
    }
}

@_cdecl("nvscene_enabled")
func nvSceneEnabled() -> Int32 { NvSwiftScene.enabled ? 1 : 0 }
@_cdecl("nvscene_wait_frame")
func nvSceneWaitFrame() { if NvSwiftScene.enabled { NvSceneClock.shared.wait() } }
@_cdecl("nvscene_begin")
func nvSceneBegin(_ screen: UnsafePointer<CChar>?, _ r: Float, _ g: Float, _ b: Float) {
    NvSwiftScene.shared.begin(screen: screen.map(String.init(cString:)) ?? "unknown",
                             background: UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1))
}
@_cdecl("nvscene_draw")
func nvSceneDraw(_ command: UnsafePointer<NvSceneCommand>?) { if let command { NvSwiftScene.shared.draw(command.pointee) } }
@_cdecl("nvscene_end")
func nvSceneEnd() { NvSwiftScene.shared.end() }
@_cdecl("nvscene_dissolve")
func nvSceneDissolve(_ alpha: Float) { NvSwiftScene.shared.dissolve(CGFloat(alpha)) }
@_cdecl("nvscene_target_bind")
func nvSceneTargetBind(_ framebuffer: UInt32) { NvSwiftScene.shared.bind(framebuffer: framebuffer) }
@_cdecl("nvscene_target_attach")
func nvSceneTargetAttach(_ framebuffer: UInt32, _ texture: UInt32) { NvSwiftScene.shared.attach(framebuffer: framebuffer, texture: texture) }
@_cdecl("nvscene_framebuffer_delete")
func nvSceneFramebufferDelete(_ framebuffer: UInt32) { NvSwiftScene.shared.removeFramebuffer(framebuffer) }
@_cdecl("nvscene_clear")
func nvSceneClear(_ r: Float, _ g: Float, _ b: Float, _ a: Float, _ clipped: Int32,
                  _ x: Int32, _ y: Int32, _ w: Int32, _ h: Int32, _ vw: Int32, _ vh: Int32) {
    NvSwiftScene.shared.clear(color: UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)),
                              clipped: clipped != 0, pixelRect: CGRect(x: Int(x), y: Int(y), width: Int(w), height: Int(h)),
                              viewport: CGSize(width: Int(vw), height: Int(vh)))
}
@_cdecl("nvscene_target_begin")
func nvSceneTargetBegin(_ id: UInt32, _ w: Int32, _ h: Int32, _ x: Float, _ y: Float, _ scale: Float, _ clear: Int32) {
    NvSwiftScene.shared.targetBegin(id, width: Int(w), height: Int(h), clear: clear != 0)
}
@_cdecl("nvscene_target_end")
func nvSceneTargetEnd() { NvSwiftScene.shared.targetEnd() }
@_cdecl("nvscene_read_pixels")
func nvSceneReadPixels(_ x: Int32, _ y: Int32, _ w: Int32, _ h: Int32, _ format: Int32,
                       _ alignment: Int32, _ vw: Int32, _ vh: Int32, _ bytes: UnsafeMutableRawPointer?) -> Int32 {
    guard let bytes else { return 0 }
    return NvSwiftScene.shared.readPixels(x: Int(x), y: Int(y), width: Int(w), height: Int(h), format: Int(format),
        alignment: Int(alignment), viewport: CGSize(width: Int(vw), height: Int(vh)), destination: bytes) ? 1 : 0
}
