import UIKit

extension NvSceneRect {
    var cg: CGRect { CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h)) }
}
extension NvSceneColor {
    var ui: UIColor { UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)) }
}

func nvSceneCommandsEqual(_ lhs: NvSceneCommand, _ rhs: NvSceneCommand) -> Bool {
    var lhs = lhs, rhs = rhs
    return withUnsafeBytes(of: &lhs) { a in
        withUnsafeBytes(of: &rhs) { b in
            memcmp(a.baseAddress!, b.baseAddress!, a.count) == 0
        }
    }
}

// Every visual mode has an explicit Swift implementation. Native image/text
// views keep immutable content while UIKit moves their frames during scrolling.
// Decorative paths are cached by the view's backing layer between changes.
final class NvScenePrimitive: UIView {
    private var image: UIImageView?
    private var secondary: UIImageView?
    private var text: NvSceneLabel?
    private var ornament: NvSceneOrnament?
    private var effect: UIVisualEffectView?
    private var resourceRevision: UInt64 = .max
    private var source: NvSceneCommand?
    private struct ImageContent: Equatable {
        let id: UInt32, revision: UInt64
        let opaque: Bool, blur: Int, tint: Int
        let red: Float, green: Float, blue: Float
    }
    private var imageContent: ImageContent?
    private var secondaryContent: ImageContent?
    private let clipView = UIView()
    private static let imageModes: Set<Int32> = [0, 3, 5, 6, 8, 10, 11, 12, 16, 19, 20, 22, 25, 34, 36, 37, 38, 39, 41, 42, 44, 46, 48, 49, 50, 51, 52, 53]
    private static let opaqueModes: Set<Int32> = [0, 3, 6, 11, 12, 20, 22, 34, 37, 38, 39, 44, 46, 48]
    private static let pixelOnlyModes: Set<Int32> = [5, 8, 10, 16, 19, 25, 36, 41, 49, 50, 51, 52, 53]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
        clipView.isUserInteractionEnabled = false
        addSubview(clipView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // A rectangle needs no bitmap or label. Create only the content a command
    // uses, retaining it when that draw slot is reused on the following frame.
    private func attach(_ child: UIView, order: Int) {
        child.tag = order; child.frame = clipView.bounds
        child.isUserInteractionEnabled = false; child.backgroundColor = .clear
        if let next = clipView.subviews.first(where: { $0.tag > order }) {
            clipView.insertSubview(child, belowSubview: next)
        } else { clipView.addSubview(child) }
    }
    private func imageView(second: Bool = false) -> UIImageView {
        if let view = second ? secondary : image { return view }
        let view = UIImageView()
        view.layer.minificationFilter = .trilinear; view.clipsToBounds = true
        attach(view, order: second ? 1 : 2)
        if second { secondary = view } else { image = view }
        return view
    }

    func update(_ c: NvSceneCommand) {
        let resources = NvSceneResources.shared
        let revision = resources.generation(c.texture) &* 31 &+ resources.generation(c.texture2)
        if let source, nvSceneCommandsEqual(source, c), resourceRevision == revision { return }
        source = c; resourceRevision = revision
        let rect = c.rect.cg
        let clip = c.flags & 1 != 0 ? rect.intersection(c.clip.cg) : rect
        transform = .identity
        let nextFrame = clip.isNull ? CGRect.zero : clip
        if frame != nextFrame { frame = nextFrame }
        clipsToBounds = c.flags & 1 != 0
        let contentFrame = CGRect(x: rect.minX - frame.minX, y: rect.minY - frame.minY,
                                  width: rect.width, height: rect.height)
        if clipView.frame != contentFrame { clipView.frame = contentFrame }
        clipView.clipsToBounds = true
        let solid = c.mode == 2 || c.mode == 21
        clipView.backgroundColor = solid ? c.color.ui.withAlphaComponent(1) :
            ([0, 46].contains(c.mode) ? UIColor(white: 0.173, alpha: 1) : .clear)
        let radius = max(0, min(CGFloat(c.radius) * rect.height, min(rect.width, rect.height) / 2))
        clipView.layer.cornerRadius = c.mode == 19 || c.mode == 21 ? min(rect.width, rect.height) / 2 : radius
        alpha = c.flags & 64 != 0 ? 1 : CGFloat(max(0, min(1, c.color.a)))
        if c.rotation != 0 {
            let center = CGPoint(x: CGFloat(c.centerX), y: CGFloat(c.centerY))
            let own = CGPoint(x: frame.midX, y: frame.midY)
            transform = CGAffineTransform(translationX: center.x - own.x, y: center.y - own.y)
                .rotated(by: CGFloat(c.rotation))
                .translatedBy(x: own.x - center.x, y: own.y - center.y)
        }
        let children: [UIView?] = [image, secondary, text, ornament]
        for child in children.compactMap({ $0 }) {
            if child.frame != clipView.bounds { child.frame = clipView.bounds }
        }
        let definition = c.mode == 5 ? resources.texts[c.texture] : nil
        let usesImage = definition == nil && Self.imageModes.contains(c.mode) && c.texture != 0
        // Do not hide/show retained content as part of every update. Toggling
        // visibility dirties the layer tree even when only its position moves.
        if !usesImage { image?.isHidden = true }
        if !usesImage || c.flags & 64 == 0 { secondary?.isHidden = true }
        text?.isHidden = definition == nil
        ornament?.isHidden = definition != nil || solid || Self.pixelOnlyModes.contains(c.mode)
        effect?.isHidden = definition != nil || c.mode != 43
        if let definition {
            let label: NvSceneLabel
            if let text { label = text } else {
                label = NvSceneLabel(); attach(label, order: 3); text = label
            }
            label.isHidden = false
            label.apply(definition, tint: c.parx > 0.5 ? c.color.ui : nil,
                        brightness: CGFloat(1 - c.focus))
            accessibilityLabel = definition.text
        } else {
            accessibilityLabel = nil
            if Self.imageModes.contains(c.mode), c.texture != 0 {
                let image = imageView()
                let blur = c.mode == 6 || c.mode == 10 ? max(2, CGFloat(c.focus) * 3) : 0
                let tint = c.mode == 16 ? 1 : (c.mode == 5 && c.parx > 0.5 ? 2 : 0)
                let key = ImageContent(id: c.texture, revision: revision,
                    opaque: Self.opaqueModes.contains(c.mode), blur: Int(blur * 4), tint: tint,
                    red: tint == 0 ? 0 : c.color.r, green: tint == 0 ? 0 : c.color.g, blue: tint == 0 ? 0 : c.color.b)
                if imageContent != key {
                    image.image = resources.image(c.texture, opaque: key.opaque, blur: blur)
                    if tint == 1 {
                        image.image = image.image?.withRenderingMode(.alwaysTemplate)
                        image.tintColor = c.color.ui.withAlphaComponent(1)
                    } else if tint == 2 {
                        image.image = image.image?.withTintColor(c.color.ui.withAlphaComponent(1), renderingMode: .alwaysOriginal)
                    }
                    imageContent = key
                }
                image.isHidden = image.image == nil || ([3, 12].contains(c.mode) && c.parx > 0.5)
                let mode = imageMode(c), uv = contentsRect(c)
                if image.contentMode != mode { image.contentMode = mode }
                if image.layer.contentsRect != uv { image.layer.contentsRect = uv }
                let sampler = resources.sampling(c.texture)
                image.layer.minificationFilter = sampler.0; image.layer.magnificationFilter = sampler.1
                if c.slide != 0 { image.frame.origin.x += CGFloat(c.slide) * clipView.bounds.width }
                image.alpha = c.flags & 64 != 0 ? CGFloat(c.color.a) : 1
                if c.flags & 64 != 0, let second = resources.image(c.texture2, opaque: true) {
                    let view = imageView(second: true)
                    let key = ImageContent(id: c.texture2, revision: revision, opaque: true, blur: 0, tint: 0,
                                           red: 0, green: 0, blue: 0)
                    if secondaryContent != key { view.image = second; secondaryContent = key }
                    view.isHidden = false; view.contentMode = .scaleAspectFill; view.alpha = CGFloat(c.alpha2)
                } else {
                    secondary?.isHidden = true
                }
            }
            if c.mode == 43 {
                if effect == nil {
                    let view = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
                    attach(view, order: 0); effect = view
                }
                effect?.frame = clipView.bounds; effect?.isHidden = false
            }
            if !solid && !Self.pixelOnlyModes.contains(c.mode) {
                let decoration: NvSceneOrnament
                if let ornament { decoration = ornament } else {
                    decoration = NvSceneOrnament(); attach(decoration, order: 4); ornament = decoration
                }
                decoration.isHidden = false; decoration.apply(c)
            }
        }
    }

    private func imageMode(_ c: NvSceneCommand) -> UIView.ContentMode {
        if [5, 8, 16, 25, 36, 41, 49, 50, 51, 52, 53].contains(c.mode) || c.aspect == 0 { return .scaleToFill }
        if [0, 46].contains(c.mode) && c.flags & 2 == 0 && c.aspect > 1.2 && c.rect.w < c.rect.h { return .scaleAspectFit }
        return .scaleToFill
    }
    private func contentsRect(_ c: NvSceneCommand) -> CGRect {
        if c.mode == 42 { return c.uv.cg }
        var uv = CGRect(x: 0, y: 0, width: 1, height: 1)
        if imageMode(c) == .scaleAspectFit || [5, 8, 16, 25, 36, 41, 49, 50, 51, 52, 53].contains(c.mode) { return uv }
        let targetAspect = c.mode == 39 ? CGFloat(1920.0 / 1080.0) : CGFloat(c.rect.w / c.rect.h)
        let aspect = CGFloat(c.aspect)
        if aspect > 0, targetAspect > 0 {
            if aspect > targetAspect {
                uv.size.width = targetAspect / aspect
                uv.origin.x = (1 - uv.width) * (c.mode == 48 ? CGFloat(max(0, min(1, c.pary))) : 0.5)
            }
            else {
                uv.size.height = aspect / targetAspect
                let anchor = [34, 44].contains(c.mode) ? CGFloat(max(0, min(1, c.parx))) : 0.5
                uv.origin.y = (1 - uv.height) * anchor
            }
        }
        if c.mode == 39, c.uv.w > 0, c.uv.h > 0 {
            return CGRect(x: uv.minX + CGFloat(c.uv.x) * uv.width, y: uv.minY + CGFloat(c.uv.y) * uv.height,
                          width: CGFloat(c.uv.w) * uv.width, height: CGFloat(c.uv.h) * uv.height)
        }
        return uv
    }
}

private final class NvSceneLabel: UILabel {
    private var definition: NvSceneText?
    private var lastTint: UIColor?
    private var lastBrightness: CGFloat = -1
    private var lastHeight: CGFloat = -1
    func apply(_ value: NvSceneText, tint: UIColor?, brightness: CGFloat) {
        guard definition != value || lastTint != tint || lastBrightness != brightness || lastHeight != bounds.height else { return }
        definition = value
        lastTint = tint; lastBrightness = brightness; lastHeight = bounds.height
        let scale = value.lineHeight > 0 ? bounds.height / value.lineHeight : 1
        font = NvSceneResources.shared.font(for: value).withSize(value.size * scale)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        value.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        if let tint {
            var tr: CGFloat = 1, tg: CGFloat = 1, tb: CGFloat = 1, ta: CGFloat = 1
            tint.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
            red *= tr; green *= tg; blue *= tb
        }
        textColor = UIColor(red: red * brightness, green: green * brightness,
                            blue: blue * brightness, alpha: alpha)
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = .natural
        paragraph.alignment = .natural
        paragraph.lineBreakMode = .byClipping
        attributedText = NSAttributedString(string: value.text, attributes: [
            .font: font as Any, .foregroundColor: textColor as Any,
            .kern: value.tracking * scale, .paragraphStyle: paragraph,
        ])
        numberOfLines = 1
        // CoreText and FreeType can differ by a fraction of a glyph. Keep the
        // core's measured wrapping/geometry without clipping its last letter.
        adjustsFontSizeToFitWidth = true
        minimumScaleFactor = 0.95
        isAccessibilityElement = true
        accessibilityLabel = value.text
    }
    override func drawText(in rect: CGRect) {
        // SDL's line origin is its FreeType ascent, not UILabel's vertical
        // centre. Align that baseline while CoreText performs native shaping.
        let top = definition.map { $0.ascent * (bounds.height / max(1, $0.lineHeight)) - font.ascender } ?? 0
        super.drawText(in: CGRect(x: rect.minX, y: top, width: rect.width + 2,
                                  height: max(rect.height, font.lineHeight)))
    }
}

private final class NvSceneOrnament: UIView {
    private var command: NvSceneCommand?
    private var ring: CAShapeLayer?
    private var ringSize = CGSize.zero
    private var ringRadius: CGFloat = -1
    private static let softModes: Set<Int32> = [0, 1, 3, 4, 6, 7, 11, 12, 17, 18, 20, 22, 23, 24, 26, 31, 33, 34, 35, 37, 38, 39, 40, 42, 43, 44, 45, 46, 47, 48]
    private func rasterScale(_ mode: Int32) {
        // These are smooth light/alpha fields, not artwork or typography.
        // Half a design pixel is sufficient for them; images, labels, icons
        // and the separate vector focus ring retain the screen's resolution.
        let scale: CGFloat = Self.softModes.contains(mode) ? 0.5 : max(1, traitCollection.displayScale)
        if contentScaleFactor != scale { contentScaleFactor = scale }
        ring?.contentsScale = max(1, traitCollection.displayScale)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let command { rasterScale(command.mode) }
    }
    private func updateRing(_ c: NvSceneCommand) {
        let visible = (c.mode == 0 || c.mode == 46) && c.border > 0 && c.focus > 0.004
        guard visible else { ring?.isHidden = true; return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if ring == nil {
            let edge = CAShapeLayer(); edge.fillColor = UIColor.clear.cgColor
            edge.strokeColor = UIColor.white.cgColor; edge.lineWidth = 1.4
            layer.addSublayer(edge); ring = edge
        }
        guard let ring else { return }
        ring.isHidden = false; ring.opacity = c.focus * c.border * 0.35
        ring.frame = bounds; ring.contentsScale = max(1, traitCollection.displayScale)
        let radius = max(0, CGFloat(c.radius) * bounds.height - 0.7)
        if ringSize != bounds.size || ringRadius != radius {
            ring.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.7, dy: 0.7), cornerRadius: radius).cgPath
            ringSize = bounds.size; ringRadius = radius
        }
    }
    func apply(_ value: NvSceneCommand) {
        rasterScale(value.mode); updateRing(value)
        // Most shader arguments describe image motion or inherited GL state.
        // A retained decoration depends only on the inputs actually painted
        // below. Hero parallax/fade must not repaint a full-screen gradient.
        let c = value
        var style = NvSceneCommand()
        style.mode = c.mode; style.rect.w = c.rect.w; style.rect.h = c.rect.h
        switch c.mode {
        case 0, 46:
            style.focus = c.focus; style.reflect = c.reflect
            style.radius = c.radius; style.grad0 = c.grad0
            style.bottom0 = c.bottom0; style.bottomAlpha0 = c.bottomAlpha0
            style.bottom1 = c.bottom1; style.bottomAlpha1 = c.bottomAlpha1
            style.flags = c.flags & 4
            if style.flags != 0 { style.rect.y = c.rect.y }
        case 1, 26:
            style.color = c.color; style.focus = c.focus
            if c.mode == 26 { style.parx = c.parx; style.pary = c.pary }
        case 3, 12, 37, 38, 20, 22, 30:
            style.background = c.background
        case 6, 42: style.parx = c.parx
        case 7, 17, 23: style.color = c.color
        case 9, 14, 15, 27:
            style.color = c.color
            if c.mode == 14 { style.parx = c.parx }
        case 11, 39:
            style.background = c.background
            if c.mode == 39 { style.parx = c.parx }
        case 13, 32:
            style.color = c.color; style.parx = c.parx; style.pary = c.pary; style.radius = c.radius
            if c.mode == 32 { style.grad0 = c.grad0; style.grad1 = c.grad1; style.grad2 = c.grad2 }
        case 24: style.color = c.color; style.parx = c.parx; style.pary = c.pary
        case 28: style.color = c.color; style.time = c.time
        case 29: style.color = c.color; style.focus = c.focus; style.radius = c.radius; style.parx = c.parx
        case 31: style.grad0 = c.grad0; style.grad1 = c.grad1; style.grad2 = c.grad2
        case 33:
            style.background = c.background
            style.ambient0 = c.ambient0; style.ambient1 = c.ambient1
            style.ambient2 = c.ambient2; style.ambient3 = c.ambient3
        case 34, 44: style.background = c.background; style.focus = c.focus; style.color.r = c.color.r
        case 35: style.color = c.color; style.focus = c.focus
        case 40: style.color = c.color; style.parx = c.parx; style.pary = c.pary; style.focus = c.focus
        case 45: style.parx = c.parx; style.pary = c.pary; style.radius = c.radius; style.focus = c.focus
        case 47: style.parx = c.parx; style.pary = c.pary; style.radius = c.radius; style.veil = c.veil
        case 48: style.parx = c.parx; style.veil = c.veil
        default: break
        }
        // Node alpha is composited separately; the decorative painter always
        // constructs opaque base RGB before applying its own gradient alpha.
        style.color.a = 1
        if let command, nvSceneCommandsEqual(command, style) { return }
        command = style; setNeedsDisplay()
    }
    override init(frame: CGRect) {
        super.init(frame: frame); isOpaque = false; contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let c = command, let context = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }
        let box = bounds, width = bounds.width, height = bounds.height
        let color = c.color.ui.withAlphaComponent(1), bg = c.background.ui.withAlphaComponent(1)
        let radius = CGFloat(c.radius) * height
        context.saveGState()
        defer { context.restoreGState() }
        context.setAllowsAntialiasing(true)
        switch c.mode {
        case 0, 46: // Poster depth, optional edge ring and lower reading veils.
            UIColor.black.withAlphaComponent(CGFloat(max(0, 1 - c.focus)) * 0.2).setFill()
            context.fill(box)
            if c.mode == 46 {
                gradient(context, colors: [.clear, c.grad0.ui], locations: [0.25, 1],
                         start: .zero, end: CGPoint(x: 0, y: height))
            }
            if c.focus > 0.004 && c.reflect > 0 {
                gradient(context, colors: [.clear, UIColor.white.withAlphaComponent(CGFloat(c.focus * c.reflect) * 0.14), .clear],
                         locations: [0, 0.5, 1], start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0))
            }
            if c.border > 0 && c.focus > 0.004 {
                context.setStrokeColor(UIColor.white.withAlphaComponent(CGFloat(c.focus * c.border) * 0.35).cgColor)
                context.setLineWidth(1.4)
                context.addPath(UIBezierPath(roundedRect: box.insetBy(dx: 0.7, dy: 0.7), cornerRadius: max(0, radius - 0.7)).cgPath)
                context.strokePath()
            }
            for (fraction, alpha) in [(c.bottom0, c.bottomAlpha0), (c.bottom1, c.bottomAlpha1)] where alpha > 0 && fraction > 0 {
                gradient(context, colors: [.clear, UIColor(white: 0.02, alpha: CGFloat(alpha))], locations: [0, 1],
                         start: CGPoint(x: 0, y: height * (1 - CGFloat(fraction))), end: CGPoint(x: 0, y: height))
            }
            if c.flags & 4 != 0 {
                let y = CGFloat(c.rect.y)
                gradient(context, colors: [UIColor.black.withAlphaComponent(0.92), .clear], locations: [0, 1],
                         start: CGPoint(x: 0, y: -y), end: CGPoint(x: 0, y: 330 - y))
                gradient(context, colors: [.clear, UIColor.black.withAlphaComponent(0.95)], locations: [0, 1],
                         start: CGPoint(x: 0, y: 780 - y), end: CGPoint(x: 0, y: 1080 - y))
            }
        case 1, 26: // Diffuse shadow / clipped corner light.
            let centre = c.mode == 26 ? CGPoint(x: width * CGFloat(c.parx), y: height * CGFloat(c.pary)) : CGPoint(x: width / 2, y: height / 2)
            radial(context, color: color.withAlphaComponent(c.mode == 1 ? CGFloat(c.focus) : 1), centre: centre,
                   radius: c.mode == 26 ? max(1, height * CGFloat(c.focus)) : max(width, height) * 0.52)
        case 2, 21:
            color.setFill(); context.fill(box)
        case 3, 12, 37, 38: // Hero art: original multi-stop reading ramps.
            let full = c.mode == 12 || c.mode == 38
            gradient(context, colors: [bg, bg.withAlphaComponent(0.86), bg.withAlphaComponent(0.56), bg.withAlphaComponent(0.16), .clear],
                     locations: [0, 0.22, 0.46, 0.76, 1], start: .zero,
                     end: CGPoint(x: width * (full ? 0.65 : 0.45), y: 0))
            gradient(context, colors: [.clear, bg.withAlphaComponent(0.25), bg.withAlphaComponent(0.65), bg],
                     locations: full ? [0.45, 0.65, 0.85, 1] : [0.82, 0.892, 0.955, 1],
                     start: .zero, end: CGPoint(x: 0, y: height))
        case 4:
            gradient(context, colors: [.clear, UIColor.black.withAlphaComponent(0.85)], locations: [0, 1], start: .zero, end: CGPoint(x: 0, y: height))
            gradient(context, colors: [UIColor.black.withAlphaComponent(0.5), .clear], locations: [0, 1], start: .zero, end: CGPoint(x: width, y: 0))
        case 5, 8, 10, 16, 19, 25, 36, 41, 49, 50, 51, 52, 53: break // Native pixels need no GL output upscaler.
        case 6:
            UIColor.black.withAlphaComponent(min(0.8, CGFloat(max(0, c.parx)))).setFill(); context.fill(box)
        case 7, 17:
            gradient(context, colors: [color.withAlphaComponent(c.mode == 7 ? 1 : 0), color.withAlphaComponent(c.mode == 7 ? 0 : 1)],
                     locations: [0, 1], start: .zero, end: CGPoint(x: 0, y: height))
        case 9, 14, 15, 27:
            symbol(context, mode: c.mode, rect: box, color: color, crossed: c.parx > 0.5)
        case 11, 39:
            gradient(context, colors: [bg.withAlphaComponent(0.9), .clear], locations: [0, 1], start: .zero, end: CGPoint(x: width * 0.7, y: 0))
            gradient(context, colors: [.clear, bg], locations: [0.35, 1], start: .zero, end: CGPoint(x: 0, y: height))
            if c.mode == 39 && c.parx > 0 { bg.withAlphaComponent(CGFloat(c.parx)).setFill(); context.fill(box) }
        case 13, 32:
            let line = max(0.6, CGFloat(c.parx) * height)
            context.setLineWidth(line); context.setStrokeColor(color.cgColor)
            if c.pary > 0 { context.setLineDash(phase: 0, lengths: [max(1, (width + height) / CGFloat(c.pary) * 0.5)]) }
            context.addPath(UIBezierPath(roundedRect: box.insetBy(dx: line / 2, dy: line / 2), cornerRadius: max(0, radius - line / 2)).cgPath)
            if c.mode == 32 { context.replacePathWithStrokedPath(); context.clip(); accent(context, c) }
            else { context.strokePath() }
        case 18:
            UIColor(red: 0.035, green: 0.025, blue: 0.04, alpha: 1).setFill(); context.fill(box)
            radial(context, color: UIColor(red: 0.31, green: 0.05, blue: 0.14, alpha: 0.45),
                   centre: CGPoint(x: width * 0.1, y: height * 0.2), radius: width * 0.8)
            radial(context, color: UIColor(red: 0.3, green: 0.12, blue: 0.13, alpha: 0.25),
                   centre: CGPoint(x: width * 0.9, y: height * 0.8), radius: width * 0.65)
        case 20:
            gradient(context, colors: [bg, .clear], locations: [0, 0.65], start: .zero, end: CGPoint(x: width, y: 0))
            gradient(context, colors: [.clear, bg], locations: [0.6, 1], start: .zero, end: CGPoint(x: 0, y: height))
        case 22:
            gradient(context, colors: [bg, .clear, .clear, bg], locations: [0, 0.12, 0.88, 1], start: .zero, end: CGPoint(x: width, y: 0))
        case 23:
            gradient(context, colors: [color.withAlphaComponent(0.06), color.withAlphaComponent(0.18), color.withAlphaComponent(0.62), color.withAlphaComponent(0.86), color.withAlphaComponent(0.95)],
                     locations: [0, 0.22, 0.52, 0.82, 1], start: .zero, end: CGPoint(x: 0, y: height))
        case 24:
            let reversed = c.pary > 0
            gradient(context, colors: [color, .clear], locations: [0, 1],
                     start: CGPoint(x: 0, y: reversed ? height : 0),
                     end: CGPoint(x: 0, y: height * CGFloat(reversed ? 1 - c.parx : c.parx)))
        case 28:
            color.setFill(); context.fill(box)
            let phase = CGFloat((c.time * 0.7).truncatingRemainder(dividingBy: 1))
            gradient(context, colors: [.clear, UIColor.white.withAlphaComponent(0.1), .clear], locations: [0, 0.5, 1],
                     start: CGPoint(x: (phase * 2 - 1) * width, y: 0), end: CGPoint(x: phase * 2 * width, y: 0))
        case 29:
            context.setStrokeColor(color.cgColor); context.setLineWidth(max(0.5, CGFloat(c.focus) * height * 2))
            context.setLineCap(.round)
            context.move(to: CGPoint(x: CGFloat(c.radius) * height, y: c.parx > 0.5 ? height : 0))
            context.addLine(to: CGPoint(x: width - CGFloat(c.radius) * height, y: c.parx > 0.5 ? 0 : height))
            context.strokePath()
        case 30:
            bg.setFill(); context.fill(box)
            radial(context, color: color.withAlphaComponent(0.18), centre: CGPoint(x: width * 0.7, y: height * 0.3), radius: width * 0.65)
            // Deterministic stars; no random resource churn on every frame.
            for n in 0..<96 {
                let x = CGFloat((n * 719 + 113) % 1920) / 1920 * width
                let y = CGFloat((n * 433 + 71) % 1080) / 1080 * height
                UIColor.white.withAlphaComponent(0.15 + CGFloat(n % 5) * 0.08).setFill()
                context.fillEllipse(in: CGRect(x: x, y: y, width: n % 7 == 0 ? 2 : 1, height: n % 7 == 0 ? 2 : 1))
            }
        case 31: accent(context, c)
        case 33:
            bg.setFill(); context.fill(box)
            for (i, ambient) in [c.ambient0, c.ambient1, c.ambient2, c.ambient3].enumerated() {
                radial(context, color: ambient.ui.withAlphaComponent(0.32),
                       centre: [CGPoint(x: 0, y: height * 0.4), CGPoint(x: width, y: height * 0.4),
                                CGPoint(x: width * 0.5, y: 0), CGPoint(x: width * 0.5, y: height)][i], radius: width * 0.7)
            }
        case 34, 44:
            let strength = CGFloat(max(0, min(1, c.focus)))
            gradient(context, colors: [bg.withAlphaComponent(0.8 * strength), .clear], locations: [0, 1], start: .zero, end: CGPoint(x: width * 0.65, y: 0))
            gradient(context, colors: [.clear, bg], locations: [CGFloat(c.color.r > 0 ? c.color.r : 0.38), 1], start: .zero, end: CGPoint(x: 0, y: height))
        case 35:
            gradient(context, colors: [color, color.withAlphaComponent(1)], locations: [0, 1], start: .zero, end: CGPoint(x: 0, y: height))
            gradient(context, colors: [.clear, UIColor.black.withAlphaComponent(CGFloat(1 - c.focus))], locations: [0, 1], start: .zero, end: CGPoint(x: 0, y: height))
        case 40:
            let edge = Int(c.parx), span = CGFloat(max(0.001, c.pary))
            let start = edge == 0 ? CGPoint(x: 0, y: height) : edge == 3 ? CGPoint(x: width, y: 0) : .zero
            let end = edge == 0 ? CGPoint(x: 0, y: height * (1 - span)) : edge == 1 ? CGPoint(x: 0, y: height * span) :
                edge == 2 ? CGPoint(x: width * span, y: 0) : CGPoint(x: width * (1 - span), y: 0)
            let colors = (0...16).map { n -> UIColor in
                let t = CGFloat(n) / 16
                let a = c.focus > 0 ? pow(1 - t, CGFloat(c.focus)) : 1 - t * t * (3 - 2 * t)
                return color.withAlphaComponent(a)
            }
            gradient(context, colors: colors, locations: (0...16).map { CGFloat($0) / 16 }, start: start, end: end)
        case 42:
            UIColor.black.withAlphaComponent(CGFloat(max(0, c.parx))).setFill(); context.fill(box)
        case 43:
            gradient(context, colors: [UIColor(white: 0.09, alpha: 0.7), UIColor(white: 0.05, alpha: 0.85)],
                     locations: [0, 1], start: .zero, end: CGPoint(x: 0, y: height))
            UIColor.white.withAlphaComponent(0.1).setStroke()
            context.setLineWidth(1); context.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        case 45: // Stage spotlight: a soft ellipse around the focused poster.
            let center = CGPoint(x: width * CGFloat(c.parx), y: height * CGFloat(c.pary))
            let rx = max(1, height * CGFloat(c.radius)), ry = max(1, height * CGFloat(c.focus))
            context.translateBy(x: center.x, y: center.y); context.scaleBy(x: rx, y: ry)
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.clear.cgColor, UIColor.clear.cgColor, UIColor(white: 0.015, alpha: 1).cgColor] as CFArray,
                locations: [0, 0.45, 1]) {
                context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero,
                    endRadius: 1.4, options: [.drawsAfterEndLocation])
            }
        case 47:
            let center = CGPoint(x: width * CGFloat(c.parx), y: height * CGFloat(c.pary))
            context.translateBy(x: center.x, y: center.y); context.scaleBy(x: 1, y: 0.23)
            radial(context, color: c.veil.ui.withAlphaComponent(0.35), centre: .zero, radius: max(1, height * CGFloat(c.radius)))
        case 48:
            if Int(c.parx) == 3 { UIColor.black.withAlphaComponent(0.4).setFill(); context.fill(box) }
            if Int(c.parx) == 4 { c.veil.ui.withAlphaComponent(0.3).setFill(); context.fill(box) }
            gradient(context, colors: [.clear, UIColor.black.withAlphaComponent(0.9)], locations: [0.35, 1],
                     start: .zero, end: CGPoint(x: 0, y: height))
            if Int(c.parx) == 0 {
                gradient(context, colors: [UIColor.black, .clear], locations: [0, 0.6], start: .zero, end: CGPoint(x: width, y: 0))
            }
        default:
            assertionFailure("Unmapped presentation mode \(c.mode)")
        }
    }
    private func accent(_ context: CGContext, _ command: NvSceneCommand) {
        gradient(context, colors: [command.grad0.ui, command.grad1.ui, command.grad2.ui], locations: [0, 0.5, 1],
                 start: .zero, end: CGPoint(x: bounds.width, y: bounds.height))
    }
    private func gradient(_ context: CGContext, colors: [UIColor], locations: [CGFloat], start: CGPoint, end: CGPoint) {
        guard start != end, let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                     colors: colors.map(\.cgColor) as CFArray, locations: locations) else { return }
        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    private func radial(_ context: CGContext, color: UIColor, centre: CGPoint, radius: CGFloat) {
        guard radius > 0, let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                   colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                                                   locations: [0, 1]) else { return }
        context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                   endRadius: radius, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    private func symbol(_ context: CGContext, mode: Int32, rect: CGRect, color: UIColor, crossed: Bool) {
        let name = mode == 9 ? "play.fill" : mode == 14 ? (crossed ? "eye.slash" : "eye") : mode == 15 ? "list.bullet" : "bell.fill"
        let configuration = UIImage.SymbolConfiguration(pointSize: max(1, rect.height * 0.8), weight: .semibold)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }
}
