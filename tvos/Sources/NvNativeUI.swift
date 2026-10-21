// Native tvOS controls over the existing design. Geometry comes from the same
// layout pass that paints the app, so themes, custom shelves and modal layers
// keep their exact positions. Focus never generates a second directional key.
import UIKit
import QuartzCore

private final class NvNativeControl: UIControl {
    let identity: UInt64
    weak var owner: NvNativeSurface?
    var customAction = false
    private var customSelectHeld = false
    private var held = Set<Int32>()

    init(identity: UInt64, owner: NvNativeSurface) {
        self.identity = identity
        self.owner = owner
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        accessibilityIdentifier = "native-control-\(identity)"
        accessibilityTraits = .button
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeFocused: Bool { owner?.active == true && !isHidden }
    var selecting: Bool { held.contains(4) }
    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        if context.previouslyFocusedView === self && selecting &&
            !context.focusHeading.isEmpty && context.nextFocusedView is NvNativeControl { return false }
        return super.shouldUpdateFocus(in: context)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                 with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if context.previouslyFocusedView === self && context.nextFocusedView !== self { releaseKeys() }
        if context.nextFocusedView === self {
            owner?.didFocus()
            if nvui_focus(identity) == 0 { owner?.invalidateControl(identity) }
        }
    }
    private func key(_ type: UIPress.PressType) -> Int32? {
        switch type {
        case .select: return 4
        case .menu: return 5
        case .playPause: return 6
        default: return nil
        }
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var rest = Set<UIPress>()
        for press in presses {
            if let key = key(press.type), held.insert(key).inserted {
                if key == 4 && customAction { customSelectHeld = true }
                else { nvui_key(key, 1) }
            }
            else if key(press.type) == nil { rest.insert(press) }
        }
        // Let UIKit process directions. NvRemote replaces only SDL's parent
        // responder while this surface owns focus, preventing duplicate keys.
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }
    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.filter { key($0.type) == nil }
        if !rest.isEmpty { super.pressesChanged(Set(rest), with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var rest = Set<UIPress>()
        for press in presses {
            if let key = key(press.type), held.remove(key) != nil {
                if key == 4 && customSelectHeld {
                    customSelectHeld = false
                    if owner?.active == true { _ = nvui_activate(identity) }
                } else { nvui_key(key, 0) }
            }
            else if key(press.type) == nil { rest.insert(press) }
        }
        if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseKeys()
        let rest = presses.filter { key($0.type) == nil }
        if !rest.isEmpty { super.pressesCancelled(Set(rest), with: event) }
    }
    func releaseKeys() {
        for key in held where key != 4 || !customSelectHeld { nvui_key(key, 0) }
        customSelectHeld = false
        held.removeAll()
    }
}

private final class NvNativeSurface: UIView {
    static let shared = NvNativeSurface()
    private(set) var active = false
    var enabled = false
    var home = false
    private var controls: [UInt64: NvNativeControl] = [:]
    private var preferred: UInt64 = 0
    private var needsFallback: UIFocusHeading = []
    private var fallbackOrigin: CGRect = .zero
    private var fallbackFrames = 0
    private var labels: [UInt64: String] = [:]
    private var order: [UInt64] = []
    private var observers: [NSObjectProtocol] = []
#if DEBUG
    private var lastDiagnostic = ""
    private var lastFocusDiagnostic = ""
    private var sceneProbe: UILabel?
#endif

    private init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isHidden = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIFocusSystem.movementDidFailNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let self, self.active,
                  let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
                  let from = context.previouslyFocusedView as? NvNativeControl, from.owner === self,
                  !from.selecting,
                  self.window?.windowScene?.focusSystem?.focusedItem as? UIView === from,
                  !context.focusHeading.isEmpty, self.needsFallback.isEmpty else { return }
            let heading = context.focusHeading
            // UIKit can report a failed intermediate candidate during a focus
            // transaction which subsequently succeeds. Wait until it commits.
            DispatchQueue.main.async { [weak self, weak from] in
                guard let self, let from, self.active, self.needsFallback.isEmpty,
                      self.window?.windowScene?.focusSystem?.focusedItem as? UIView === from else { return }
                self.needsFallback = heading
                self.fallbackOrigin = from.frame
                self.fallbackFrames = 0
                let key: Int32? = heading.contains(.up) ? 0 : heading.contains(.down) ? 1 :
                    heading.contains(.left) ? 2 : heading.contains(.right) ? 3 : nil
                if let key { nvui_key(key, 1); nvui_key(key, 0) }
            }
        })
        observers.append(center.addObserver(forName: UIScene.willDeactivateNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.cancelInput()
        })
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let target = controls[preferred] { return [target] }
        return controls.values.sorted { a, b in
            abs(a.frame.minY - b.frame.minY) > 8 ? a.frame.minY < b.frame.minY : a.frame.minX < b.frame.minX
        }.prefix(1).map { $0 }
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard active else { return nil }
        let target = super.hitTest(point, with: event)
        return target === self ? nil : target
    }
    private var windowForSDL: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .first { $0.rootViewController.map { String(describing: type(of: $0)).contains("SDL") } == true ||
                $0.rootViewController?.view.layer is CAEAGLLayer }
    }
    private func install() -> Bool {
        guard let window = windowForSDL, let root = window.rootViewController else { return false }
        if superview !== root.view {
            removeFromSuperview()
            frame = root.view.bounds
            root.view.addSubview(self)
        }
        // The legacy receiver may be installed after our first frame. Although
        // clear, a frontmost UIFocusItem can occlude other focus candidates.
        if root.view.subviews.last !== self { root.view.bringSubviewToFront(self) }
        return true
    }
    func begin(home: Bool, enabled: Bool) {
        self.home = home
        labels.removeAll(keepingCapacity: true)
        self.enabled = enabled && ProcessInfo.processInfo.environment["NUVIO_NATIVE_UI"] != "0"
        NvPosterSurface.shared.begin(enabled: self.enabled && home && !NvSwiftScene.enabled)
    }
    func publish(_ list: UnsafePointer<NvUIControl>?, count: Int, preferred: UInt64) {
#if DEBUG
        if ProcessInfo.processInfo.environment["NUVIO_NATIVE_UI_STATS"] == "1" {
            let present = list.map { UnsafeBufferPointer(start: $0, count: min(max(0, count), 512)).contains { $0.identity == preferred } } ?? false
            let state = "enabled=\(enabled) count=\(count) preferred=\(preferred != 0) listed=\(present)"
            if state != lastDiagnostic { print("[native-input] \(state)"); lastDiagnostic = state }
        }
#endif
        guard enabled, preferred != 0, install(), let list, count > 0 else {
            active = false
            isHidden = true
            controls.values.forEach { $0.releaseKeys(); $0.removeFromSuperview() }
            controls.removeAll()
            order.removeAll()
            needsFallback = []
            return
        }
        var seen = Set<UInt64>()
        var newOrder: [UInt64] = []
        let sx = bounds.width / 1920, sy = bounds.height / 1080
        UIView.performWithoutAnimation {
            for entry in UnsafeBufferPointer(start: list, count: min(count, 512)) {
                guard entry.w.isFinite, entry.h.isFinite, entry.x.isFinite, entry.y.isFinite,
                      entry.w > 0, entry.h > 0 else { continue }
                let id = entry.identity
                let control = controls[id] ?? NvNativeControl(identity: id, owner: self)
                controls[id] = control
                control.customAction = entry.flags & 1 != 0
                if let text = labels[id] ?? NvSwiftScene.shared.label(in: CGRect(x: CGFloat(entry.x), y: CGFloat(entry.y),
                                                    width: CGFloat(entry.w), height: CGFloat(entry.h))) {
                    control.accessibilityLabel = text
                }
                if control.superview == nil { addSubview(control) }
                let rect = CGRect(x: CGFloat(entry.x) * sx, y: CGFloat(entry.y) * sy,
                                  width: CGFloat(entry.w) * sx, height: CGFloat(entry.h) * sy)
                if control.frame != rect { control.frame = rect }
                control.isHidden = false
                seen.insert(id)
                newOrder.append(id)
            }
            if order != newOrder {
                for id in newOrder { if let view = controls[id] { bringSubviewToFront(view) } }
                order = newOrder
            }
            for id in Set(controls.keys).subtracting(seen) {
                controls[id]?.releaseKeys()
                controls.removeValue(forKey: id)?.removeFromSuperview()
            }
        }
        if preferred != 0 && controls[preferred] == nil {
            // Some internal widgets intentionally expose no native target.
            // Their existing receiver owns input until a supported target returns.
            active = false
            isHidden = true
            controls.values.forEach { $0.releaseKeys(); $0.removeFromSuperview() }
            controls.removeAll()
            order.removeAll()
            needsFallback = []
            return
        }
        self.preferred = preferred
        active = !controls.isEmpty
        isHidden = !active
    }
    func end() {
        NvPosterSurface.shared.end()
#if DEBUG
        if !NvSwiftScene.enabled, ProcessInfo.processInfo.environment["NUVIO_NATIVE_UI_STATS"] == "1",
           let window = window ?? windowForSDL {
            let probe = sceneProbe ?? UILabel(frame: CGRect(x: 1, y: 1, width: 1, height: 1))
            probe.text = "native-presentation"; probe.textColor = .clear
            probe.font = .systemFont(ofSize: 1)
            probe.isUserInteractionEnabled = false
            let focused = window.windowScene?.focusSystem?.focusedItem as? UIView
            let value = focused?.accessibilityIdentifier ?? "none"
            probe.accessibilityIdentifier = "native-presentation-\(NvSwiftScene.shared.screen)-\(value)"
            probe.accessibilityValue = value
            if probe.superview !== window { probe.removeFromSuperview(); window.addSubview(probe) }
            sceneProbe = probe
        }
#endif
        guard active, let window,
              UIApplication.shared.applicationState == .active,
              window.rootViewController?.presentedViewController == nil else { return }
        let current = window.windowScene?.focusSystem?.focusedItem as? UIView
#if DEBUG
        if ProcessInfo.processInfo.environment["NUVIO_NATIVE_UI_STATS"] == "1" {
            let state = "active=\(active) focused=\(current.map { String(describing: type(of: $0)) } ?? "none")"
            if state != lastFocusDiagnostic { print("[native-focus] \(state)"); lastFocusDiagnostic = state }
        }
#endif
        // A system alert or keyboard owns its own focus. Never reclaim it.
        if let current, !current.isDescendant(of: self), !String(describing: type(of: current)).contains("NvRemote") {
            return
        }
        let native = current as? NvNativeControl
        var target = controls[preferred]
        if target == nil && !needsFallback.isEmpty {
            // SDL consumes the queued edge-navigation key on its next loop.
            // Keep the recovery until the following complete layout is ready.
            fallbackFrames += 1
            if fallbackFrames < 2 { return }
            target = fallbackTarget(excluding: native?.identity)
        }
        needsFallback = []
        if target == nil, native?.owner === self, let native, controls[native.identity] === native { return }
        if let target { preferred = target.identity }
        if native?.identity != preferred || current == nil {
            window.rootViewController?.setNeedsFocusUpdate()
            window.rootViewController?.updateFocusIfNeeded()
        }
    }
    private func fallbackTarget(excluding id: UInt64?) -> NvNativeControl? {
        let origin = fallbackOrigin
        return controls.values.filter { v in
            guard v.identity != id else { return false }
            let dx = v.frame.midX - origin.midX, dy = v.frame.midY - origin.midY
            // The core scrolls the newly selected item into the old focus slot.
            // Selecting another row further in the movement direction skips it.
            return abs(dx) < max(origin.width, v.frame.width) * 0.55 &&
                   abs(dy) < max(origin.height, v.frame.height) * 0.55
        }.min { a, b in
            hypot(a.frame.midX - origin.midX, a.frame.midY - origin.midY) <
                hypot(b.frame.midX - origin.midX, b.frame.midY - origin.midY)
        }
    }
    func invalidateControl(_ identity: UInt64) { controls[identity]?.isHidden = true }
    func didFocus() { needsFallback = []; fallbackFrames = 0 }
    func label(_ identity: UInt64, text: String) {
        labels[identity] = text
        controls[identity]?.accessibilityLabel = text
    }
    func cancelInput() { controls.values.forEach { $0.releaseKeys() }; needsFallback = [] }
}

@_cdecl("nvui_frame_begin")
func nvUIFrameBegin(_ home: Int32, _ enabled: Int32) { NvNativeSurface.shared.begin(home: home != 0, enabled: enabled != 0) }
@_cdecl("nvui_controls")
func nvUIControls(_ list: UnsafePointer<NvUIControl>?, _ count: Int32, _ preferred: UInt64) {
    NvNativeSurface.shared.publish(list, count: Int(max(0, count)), preferred: preferred)
}
@_cdecl("nvui_frame_end")
func nvUIFrameEnd() { NvNativeSurface.shared.end() }
@_cdecl("nvui_owns_focus")
func nvUIOwnsFocus() -> Int32 { NvNativeSurface.shared.active ? 1 : 0 }
@_cdecl("nvui_focus_environment")
func nvUIFocusEnvironment() -> UnsafeMutableRawPointer? {
    let view = NvNativeSurface.shared
    return view.active ? Unmanaged.passUnretained(view).toOpaque() : nil
}

@_cdecl("nvui_label")
func nvUILabel(_ identity: UInt64, _ text: UnsafePointer<CChar>?) {
    guard let text else { return }
    NvNativeSurface.shared.label(identity, text: String(cString: text))
}
