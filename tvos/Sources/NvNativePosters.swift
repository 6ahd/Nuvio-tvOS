import UIKit
import QuartzCore
import GameController

// The focused poster follows the finger on the Siri Remote's touch surface, the
// way tvOS cards do: the art shifts a little inside its frame and a soft light
// glides across it. The frame itself never moves, so the GL focus ring and the
// labels drawn over it stay exactly where the C layout put them. The finger's
// position comes from the remote's micro gamepad (absolute touch-surface
// coordinates); UIKit's swipe recognizers are untouched.
final class NvParallax {
    static let shared = NvParallax()
    private(set) var x: CGFloat = 0
    private(set) var y: CGFloat = 0
    private var last = CACurrentMediaTime()
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main) { _ in NvParallax.configure() }
        NvParallax.configure()
    }
    private static func configure() {
        for controller in GCController.controllers() {
            controller.microGamepad?.reportsAbsoluteDpadValues = true
        }
    }
    /// Once per frame. Eases toward the finger (or back to the centre when it lifts).
    func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(0.05, max(0, now - last)))
        last = now
        var tx: CGFloat = 0, ty: CGFloat = 0
        if !UIAccessibility.isReduceMotionEnabled,
           let pad = GCController.controllers().lazy.compactMap({ $0.microGamepad }).first {
            tx = CGFloat(pad.dpad.xAxis.value)
            ty = CGFloat(pad.dpad.yAxis.value)
        }
        // critically damped feel at ~8/s: follows the finger without trembling
        let k = 1 - exp(-8 * dt)
        x += (max(-1, min(1, tx)) - x) * k
        y += (max(-1, min(1, ty)) - y) * k
        if abs(x) < 0.001 { x = 0 }
        if abs(y) < 0.001 { y = 0 }
    }
}

// Reuses the pixels the existing bounded image workers already decoded. There
// is no second network request or JPEG/WebP decode for the UIKit poster view.
private final class NvPosterPixels {
    static let shared = NvPosterPixels()
    let images = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    init() {
        images.totalCostLimit = 32 * 1024 * 1024
        images.countLimit = 64
    }
    func insert(url: String, bytes: UnsafeRawPointer, width: Int, height: Int, pitch: Int) {
        guard width > 0, height > width, width <= 1024, height <= 2048,
              pitch >= width * 4, pitch <= width * 4 + 4096 else { return }
        lock.lock()
        defer { lock.unlock() }
        if let old = images.object(forKey: url as NSString), let cg = old.cgImage,
           cg.width >= width { return }
        let data = Data(bytes: bytes, count: pitch * height) as CFData
        guard let provider = CGDataProvider(data: data),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8,
                               bitsPerPixel: 32, bytesPerRow: pitch,
                               space: CGColorSpaceCreateDeviceRGB(),
                               // GFX_CARD reads RGB and uses the card mask for
                               // alpha, so native portrait art follows that rule.
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
                                .union(.byteOrder32Big),
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent) else { return }
        images.setObject(UIImage(cgImage: cg), forKey: url as NSString, cost: pitch * height)
    }
}

private final class NvPosterView: UIView {
    var source = ""
    let image = UIImageView()
    let dim = UIView()
    let shine = CAGradientLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.173, alpha: 1)
        clipsToBounds = true
        isUserInteractionEnabled = false
        image.frame = bounds
        image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        image.layer.minificationFilter = .trilinear
        image.layer.magnificationFilter = .linear
        addSubview(image)
        dim.frame = bounds
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.backgroundColor = .black
        addSubview(dim)
        shine.type = .radial
        shine.colors = [UIColor(white: 1, alpha: 0.22).cgColor, UIColor(white: 1, alpha: 0).cgColor]
        shine.opacity = 0
        layer.addSublayer(shine)
    }
    /// Focused art drifts up to 3% of its size toward the finger, slightly
    /// enlarged so its edges never show; a light follows from the opposite side.
    func parallax(focus: CGFloat) {
        let f = max(0, min(1, (focus - 0.5) * 2))
        let px = NvParallax.shared.x, py = NvParallax.shared.y
        let w = bounds.width, h = bounds.height
        if f <= 0 {
            if image.transform != .identity { image.transform = .identity }
            if shine.opacity != 0 { shine.opacity = 0 }
            return
        }
        let s = 1 + 0.06 * f
        image.transform = CGAffineTransform(translationX: px * w * 0.03 * f, y: -py * h * 0.03 * f).scaledBy(x: s, y: s)
        let side = max(w, h) * 1.6
        shine.frame = CGRect(x: (w - side) / 2 - px * w * 0.35, y: (h - side) / 2 + py * h * 0.35,
                             width: side, height: side)
        shine.startPoint = CGPoint(x: 0.5, y: 0.5)
        shine.endPoint = CGPoint(x: 1, y: 1)
        shine.opacity = Float(f * min(1, 0.35 + hypot(px, py)))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// Native images sit below the translucent GL design overlay, just like the
// Aether video plane. The overlay retains the original labels, badges, progress
// bars, gradients and focus ring. A failed/missing native image uses the normal
// GL image in the same frame, so cache eviction cannot blank a poster.
final class NvPosterSurface: UIView {
    static let shared = NvPosterSurface()
    private var enabled = false
    private var views: [UInt64: NvPosterView] = [:]
    private var seen = Set<UInt64>()
    private weak var gl: UIView?
    private var memoryObserver: NSObjectProtocol?

    private init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { _ in
            NvPosterPixels.shared.images.removeAllObjects()
            // Visible views retain their images until the next complete draw.
            // Removing them here could expose a transparent hole for a frame.
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func install() -> Bool {
        func find(_ view: UIView) -> UIView? {
            if view.layer is CAEAGLLayer { return view }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        let cached = gl.flatMap { $0.window != nil ? $0 : nil }
        guard let canvas = cached ?? windows.compactMap({ find($0) }).first,
              let host = canvas.superview else { return false }
        if superview !== host {
            removeFromSuperview()
            host.insertSubview(self, belowSubview: canvas)
            frame = host.bounds
        }
        // The player inserts its plane directly below GL when a trailer starts.
        // Keep poster art above that plane, otherwise card holes show the video.
        if let position = host.subviews.firstIndex(of: canvas), position > 0,
           host.subviews[position - 1] !== self {
            host.insertSubview(self, belowSubview: canvas)
        }
        gl = canvas
        canvas.isOpaque = false
        canvas.layer.isOpaque = false
        canvas.backgroundColor = .clear
        return true
    }
    func begin(enabled: Bool) {
        self.enabled = enabled
        if enabled { NvParallax.shared.tick() }
        seen.removeAll(keepingCapacity: true)
        if enabled { self.enabled = install() }
    }
    func show(identity: UInt64, url: String, rect: CGRect, radius: CGFloat, cover: Bool, focus: CGFloat) -> Bool {
        guard enabled, !rect.isEmpty, rect.intersects(CGRect(x: 0, y: 0, width: 1920, height: 1080)) else { return false }
        let retained = views[identity].flatMap { $0.source == url ? $0.image.image : nil }
        guard let image = NvPosterPixels.shared.images.object(forKey: url as NSString) ?? retained else { return false }
        let view = views[identity] ?? NvPosterView(frame: .zero)
        views[identity] = view
        let sx = bounds.width / 1920, sy = bounds.height / 1080
        UIView.performWithoutAnimation {
            if view.superview == nil { addSubview(view) }
            let frame = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy)
            if view.frame != frame { view.frame = frame }
            view.layer.cornerRadius = radius * min(sx, sy)
            if view.image.image !== image { view.image.image = image }
            view.source = url
            let aspect = rect.width / rect.height / (image.size.width / image.size.height)
            view.image.contentMode = !cover && (aspect < 0.80 || aspect > 1.25) ? .scaleAspectFit : .scaleAspectFill
            view.dim.alpha = 0.20 * (1 - min(1, max(0, focus)))
            view.isHidden = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.parallax(focus: focus)
            CATransaction.commit()
        }
        seen.insert(identity)
        return true
    }
    func end() {
        for identity in Set(views.keys).subtracting(seen) {
            views.removeValue(forKey: identity)?.removeFromSuperview()
        }
        isHidden = seen.isEmpty
        // Keep the canvas compositable: Aether may already be opening below it.
        // Its opaque UI pixels still paint exactly as before.
    }
}

@_cdecl("nvui_image_rgba")
func nvUIImageRGBA(_ path: UnsafePointer<CChar>?, _ pixels: UnsafeRawPointer?, _ width: Int32,
                   _ height: Int32, _ pitch: Int32) {
    guard !NvSwiftScene.enabled, let path, let pixels else { return }
    autoreleasepool {
        NvPosterPixels.shared.insert(url: String(cString: path), bytes: pixels,
                                    width: Int(width), height: Int(height), pitch: Int(pitch))
    }
}

@_cdecl("nvui_poster")
func nvUIPoster(_ identity: UInt64, _ path: UnsafePointer<CChar>?, _ x: Float, _ y: Float,
                _ width: Float, _ height: Float, _ radius: Float, _ clipTop: Float,
                _ cover: Int32, _ focus: Float) -> Int32 {
    guard !NvSwiftScene.enabled, let path else { return 0 }
    return NvPosterSurface.shared.show(identity: identity, url: String(cString: path),
        rect: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height)),
        radius: CGFloat(radius), cover: cover != 0, focus: CGFloat(focus)) ? 1 : 0
}
