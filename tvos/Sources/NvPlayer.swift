// Nuvio Legacy on Apple TV: the video plane.
//
// The legacy C core (video_tvos.c) drives this exactly like Android drives
// NvPlayer.kt: open/stop/pause/seek/window/track calls go down, state events
// come back up through nv_tvos_*. Playback itself is NuvioTVOS's engine
// (AetherEngine: FFmpeg demux, VideoToolbox, AVPlayer for Dolby Vision/Atmos).
//
// The AetherPlayerView sits BEHIND SDL's GL view in the same UIWindow. While a
// video is open the GL layer is made non-opaque, so the "hole" the core punches
// (alpha 0) shows the picture underneath: same model as webOS, Tizen, Android.
//
// SDL runs its loop on the main thread on tvOS, so every entry point below is
// already on the main actor; nvp_bombear is called once per frame and polls
// the engine (no Combine plumbing needed).
import AVFoundation
import Combine
import AetherEngine
import UIKit

@MainActor
final class NvPlayer {
    static let shared = NvPlayer()

    private var engine: AetherEngine?
    private let view = AetherPlayerView()
    private var loadTask: Task<Void, Never>?
    private var session = 0
    private var active = false
    private var wantPaused = false
    private var subtitleDelayMs = 0
    private var subtitleTrackID: Int?
    private var retainedCues: [SubtitleCue] = []
    private var cueIndex = SubtitleWindowIndex()
    private var cueUpdates: AnyCancellable?
    private var glOpaqueSaved: Bool?
    /// The next open is a trailer (nvp_trailer): no display mode switch.
    var nextIsTrailer = false

    // What has already been reported to C for this session.
    private var sentReady = false
    private var sentDurationMs: Int32 = -1
    private var sentFirstFrame = false
    private var sentState: Int32 = 0
    private var sentEnded = false
    private var sentError = false
    private var sentBuffering: Bool?
    private var sentSize = (Int32(0), Int32(0))
    private var sentHDR = ""
    private var tracksSignature = ""
    private var subtitleSignature = ""
    private var cueText = ""

    // MARK: window plumbing

    private func sdlWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let all = windows.isEmpty ? UIApplication.shared.windows : windows
        return all.first { $0.rootViewController != nil } ?? all.first
    }

    /// SDL's GL view: the one backed by a CAEAGLLayer, wherever UIKit put it.
    private func glView() -> UIView? {
        func find(_ v: UIView) -> UIView? {
            if v.layer is CAEAGLLayer { return v }
            for s in v.subviews { if let f = find(s) { return f } }
            return nil
        }
        guard let window = sdlWindow() else { return nil }
        return find(window) ?? window.rootViewController?.view
    }

    private func install() {
        guard let window = sdlWindow(), let gl = glView() else {
            NSLog("[tvos] player: SDL window not found")
            return
        }
        let host = gl.superview ?? window
        if view.superview !== host {
            view.removeFromSuperview()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .black
            view.frame = host.bounds
            // Sibling directly BELOW the GL view, so the UI stays on top and
            // the core's alpha-0 hole shows the picture.
            host.insertSubview(view, belowSubview: gl)
            NSLog("[tvos] player: view under %@ in %@", "\(type(of: gl))", "\(type(of: host))")
        }
        view.isHidden = false
        window.backgroundColor = .black
        if glOpaqueSaved == nil { glOpaqueSaved = gl.layer.isOpaque }
        gl.isOpaque = false
        gl.layer.isOpaque = false
        gl.backgroundColor = .clear
    }

    private func uninstall() {
        view.isHidden = true
        if let gl = glView(), let saved = glOpaqueSaved {
            gl.layer.isOpaque = saved
            gl.isOpaque = saved
        }
        glOpaqueSaved = nil
    }

    // MARK: commands from C

    func open(url: String, headers: String, startMs: Int, generation: Int32) {
        stopEngine()
        let isTrailer = nextIsTrailer
        nextIsTrailer = false
        uninstall()
        guard let u = URL(string: url) ?? URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
            NSLog("[tvos] player: invalid URL")
            nv_tvos_erro_texto("URL invalida")
            nv_tvos_ev(5, -1, 0)
            return
        }
        let eng: AetherEngine
        if let e = engine {
            eng = e
        } else {
            do { eng = try AetherEngine() } catch {
                nv_tvos_erro_texto("AetherEngine: \(error)")
                nv_tvos_ev(5, -1, 0)
                return
            }
            engine = eng
            cueUpdates = eng.$subtitleCues.sink { [weak self] cues in
                guard let self else { return }
                self.retainedCues = cues
                self.cueIndex.update(cues, start: { $0.startTime }, end: { $0.endTime })
            }
        }
        install()
        eng.bind(view: view)
        eng.videoGravity = .resizeAspect

        session += 1
        let mySession = session
        active = true
        wantPaused = false
        subtitleTrackID = nil
        resetReported()

        var opts = LoadOptions()
        opts.httpHeaders = Self.parseHeaders(headers)
        // A trailer keeps the TV's mode: matching its frame rate or dynamic range makes the
        // TV resync, a black screen of 1 to 3 s before every trailer (and again after it).
        opts.matchContentEnabled = !isTrailer
        // matchContentEnabled only tells the engine what the system setting is; the switch itself is
        // the engine's display criteria handshake, which a trailer skips entirely.
        opts.suppressDisplayCriteria = isTrailer
        opts.panelIsInHDRMode = (view.window?.screen ?? UIScreen.main).currentEDRHeadroom > 1.001
        opts.panelPresentsDolbyVision = AVPlayer.availableHDRModes.contains(.dolbyVision)
        opts.audioBridgeMode = .surroundCompat
        // TrueHD Atmos and DTS:X keep their heights: AetherEngine renders the objects to APAC, which
        // reaches an Atmos receiver as Dolby MAT (tvOS 26+). Same 9.1.6 layout NuvioTV uses.
        if #available(tvOS 26.0, *), ajustes_player_apple_apac() != 0 {
            opts.objectAudioRendering = .apac(.l916)
        }
        let lower = url.lowercased()
        opts.nativeRemoteHLS = u.pathExtension.lowercased() == "m3u8" || lower.contains(".m3u8")
        opts.autoplay = true
        let start: Double? = startMs > 0 ? Double(startMs) / 1000.0 : nil

        NSLog("[tvos] player: open (start %d ms%@)", startMs, isTrailer ? ", trailer: no display switch" : "")
        loadTask = Task { @MainActor [weak self] in
            guard self?.active == true, self?.session == mySession, !Task.isCancelled else { return }
            do {
                try await eng.load(url: u, startPosition: start, options: opts)
                guard let self, self.active, self.session == mySession, !Task.isCancelled else { return }
                if startMs > 0 { nv_tvos_retomada(generation, 1) }
                if self.wantPaused { eng.pause() } else { eng.play() }
            } catch {
                guard let self, self.active, self.session == mySession, !Task.isCancelled,
                      !(error is CancellationError) else { return }
                if startMs > 0 { nv_tvos_retomada(generation, 0) }
                self.reportError("\(error)", code: Self.isNetwork(error) ? 2001 : 1000)
            }
        }
    }

    func stop() {
        stopEngine()
        uninstall()
    }

    private func stopEngine() {
        // Invalidate callbacks before cancellation: load may complete despite cancel().
        session += 1
        loadTask?.cancel()
        loadTask = nil
        if active { engine?.stop() }
        active = false
        cueText = ""
    }

    func pause(_ p: Bool) {
        wantPaused = p
        guard let eng = engine, active else { return }
        if p { eng.pause() } else { eng.play() }
    }

    func seek(ms: Int) {
        guard let eng = engine, active else { return }
        sentEnded = false
        let mySession = session
        Task { @MainActor [weak self] in
            guard let self, self.active, self.session == mySession else { return }
            await eng.seek(to: Double(max(0, ms)) / 1000.0)
        }
    }

    func volume(_ pct: Int) { engine?.volume = Float(max(0, min(100, pct))) / 100 }

    func speed(_ cent: Int) {
        guard let eng = engine, active else { return }
        eng.setRate(Float(cent) / 100)
    }

    /// Rectangle in the core's 1920x1080 layout. `fit` = aspect-fit inside it;
    /// otherwise the rectangle is exact (the core already did the math, and it
    /// may extend past the screen for crop/zoom modes).
    func window(x: Int, y: Int, w: Int, h: Int, fit: Bool) {
        guard let win = view.superview ?? sdlWindow() else { return }
        let s = (sdlWindow()?.bounds.width ?? win.bounds.width) / 1920.0
        view.frame = CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: CGFloat(w) * s, height: CGFloat(h) * s)
        engine?.videoGravity = fit ? .resizeAspect : .resize
    }

    func choose(kind: Int, value: Int) {
        guard let eng = engine else { return }
        switch kind {
        case 0:
            eng.selectAudioTrack(index: value)
        case 1:
            cueText = ""
            if value < 0 {
                subtitleTrackID = nil
                eng.clearSubtitle()
            } else {
                subtitleTrackID = value
                eng.selectSubtitleTrack(index: value)
            }
        case 2:
            subtitleDelayMs = value
        default:
            break
        }
    }

    // MARK: per-frame poll

    func pump() {
        guard let eng = engine, active else { return }

        let dur = eng.duration
        if dur > 0 {
            let ms = Int32(min(dur * 1000, Double(Int32.max)))
            if !sentReady || abs(Int(ms) - Int(sentDurationMs)) > 1000 {
                sentReady = true
                sentDurationMs = ms
                nv_tvos_ev(1, ms, 0)
            }
        }
        nv_tvos_pos(Int32(max(0, min(eng.currentTime * 1000, Double(Int32.max)))))

        switch eng.state {
        case .playing:
            if !sentReady { sentReady = true; sentDurationMs = 0; nv_tvos_ev(1, 0, 0) }
            if sentState != 2 { sentState = 2; nv_tvos_ev(2, 0, 0) }
        case .paused:
            if sentState != 3 { sentState = 3; nv_tvos_ev(3, 0, 0) }
        case .ended:
            if !sentEnded { sentEnded = true; sentState = 4; nv_tvos_ev(4, 0, 0) }
        case .error(let message):
            reportError(message, code: Self.isNetworkMessage(message) ? 2001 : 1000)
        default:
            break
        }

        if eng.hasFirstFrameReadyForDisplay && !sentFirstFrame {
            sentFirstFrame = true
            nv_tvos_ev(8, 0, 0)
            nv_tvos_ev(10, 0, 0)
        }

        let size = (eng.sourceVideoWidth, eng.sourceVideoHeight)
        if size.0 > 0, size.1 > 0, size != sentSize {
            sentSize = size
            nv_tvos_ev(6, size.0, size.1)
        }

        let buffering = eng.isBuffering
        if buffering != sentBuffering {
            sentBuffering = buffering
            nv_tvos_ev(7, buffering ? 0 : 100, 0)
        }

        reportTracks(eng)
        reportHDR(eng)
        reportSubtitle(eng)
    }

    private func reportError(_ message: String, code: Int32) {
        guard !sentError else { return }
        sentError = true
        NSLog("[tvos] player error: %@", message)
        message.withCString { nv_tvos_erro_texto($0) }
        nv_tvos_ev(5, code, 0)
    }

    private func reportTracks(_ eng: AetherEngine) {
        let audio = eng.audioTracks
        let subs = eng.subtitleTracks
        let subSig = subs.map { "s\($0.id)" }.joined(separator: ",")
        let sig = audio.map { "a\($0.id):\($0.isAtmos)" }.joined(separator: ",") + "|"
            + subSig
        guard sig != tracksSignature, !(audio.isEmpty && subs.isEmpty) else { return }
        let firstReport = tracksSignature.isEmpty
        tracksSignature = sig
        for t in audio {
            let codec = t.isAtmos && t.codec.lowercased().contains("eac3") ? "audio/eac3-joc" : t.codec
            nv_tvos_faixa(0, Int32(t.id), t.language ?? "", 0, t.name, codec, Int32(t.channels))
        }
        // A later re-read of the same subtitle list goes as audio only (the C
        // side keeps the subtitle the viewer already picked).
        if firstReport || subSig != subtitleSignature {
            subtitleSignature = subSig
            for t in subs {
                let flags: Int32 = (t.isForced ? 1 : 0) | (t.isHearingImpaired ? 2 : 0)
                nv_tvos_faixa(1, Int32(t.id), t.language ?? "", flags, t.name, t.codec, 0)
            }
        }
        let sel = audio.firstIndex { $0.id == eng.activeAudioTrackIndex } ?? 0
        nv_tvos_faixas_fim(Int32(sel), -1)
    }

    private func reportHDR(_ eng: AetherEngine) {
        let hdr: String
        switch eng.videoFormat {
        case .dolbyVision: hdr = "DolbyVision"
        case .hdr10, .hdr10Plus: hdr = "HDR10"
        case .hlg: hdr = "HLG"
        default: hdr = "none"
        }
        let atmos = eng.audioTracks.first { $0.id == eng.activeAudioTrackIndex }?.isAtmos ?? false
        let key = "\(hdr)/\(atmos)"
        guard key != sentHDR else { return }
        sentHDR = key
        nv_tvos_hdr(hdr, hdr == "DolbyVision" ? 1 : 0, atmos ? 1 : 0)
    }

    private func reportSubtitle(_ eng: AetherEngine) {
        guard subtitleTrackID != nil else { return }
        let t = eng.currentTime - Double(subtitleDelayMs) / 1000.0
        var text = ""
        var remaining = 0.0
        for index in cueIndex.candidates(around: t) {
            let cue = retainedCues[index]
            guard cue.startTime <= t && t < cue.endTime else { continue }
            if let s = cue.text, !s.isEmpty {
                text = text.isEmpty ? s : text + "\n" + s
                remaining = max(remaining, cue.endTime - t)
            }
        }
        text = Self.stripTags(text)
        guard text != cueText else { return }
        cueText = text
        nv_tvos_legenda(text, Int32(max(1, remaining * 1000)))
    }

    private func resetReported() {
        sentReady = false
        sentDurationMs = -1
        sentFirstFrame = false
        sentState = 0
        sentEnded = false
        sentError = false
        sentBuffering = nil
        sentSize = (0, 0)
        sentHDR = ""
        tracksSignature = ""
        subtitleSignature = ""
        cueText = ""
    }

    // MARK: helpers

    static func parseHeaders(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            guard let i = line.firstIndex(of: ":") else { continue }
            let name = line[..<i].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { out[name] = value }
        }
        return out
    }

    static func isNetwork(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain || isNetworkMessage("\(error)")
    }

    static func isNetworkMessage(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("network") || l.contains("timed out") || l.contains("timeout")
            || l.contains("connection") || l.contains("offline")
    }

    /// ASS override blocks and simple HTML tags out; \N to newline.
    static func stripTags(_ s: String) -> String {
        guard s.contains("{") || s.contains("<") || s.contains("\\N") || s.contains("\\n") else { return s }
        var out = s.replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n")
        out = out.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return out
    }
}

// MARK: - C entry points (declared in legacy/src/tvos.h)

private func onMain(_ body: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(body)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }
}

@_cdecl("nvp_abrir")
func nvp_abrir(_ url: UnsafePointer<CChar>?, _ cab: UnsafePointer<CChar>?, _ inicioMs: Int32, _ geracao: Int32) {
    let u = url.map { String(cString: $0) } ?? ""
    let c = cab.map { String(cString: $0) } ?? ""
    onMain { NvPlayer.shared.open(url: u, headers: c, startMs: Int(inicioMs), generation: geracao) }
}

@_cdecl("nvp_trailer")
func nvp_trailer(_ sim: Int32) { onMain { NvPlayer.shared.nextIsTrailer = sim != 0 } }

@_cdecl("nvp_parar")
func nvp_parar() { onMain { NvPlayer.shared.stop() } }

@_cdecl("nvp_pausar")
func nvp_pausar(_ p: Int32) { onMain { NvPlayer.shared.pause(p != 0) } }

@_cdecl("nvp_buscar")
func nvp_buscar(_ ms: Int32) { onMain { NvPlayer.shared.seek(ms: Int(ms)) } }

@_cdecl("nvp_volume")
func nvp_volume(_ pct: Int32) { onMain { NvPlayer.shared.volume(Int(pct)) } }

@_cdecl("nvp_janela")
func nvp_janela(_ x: Int32, _ y: Int32, _ w: Int32, _ h: Int32, _ encaixa: Int32) {
    onMain { NvPlayer.shared.window(x: Int(x), y: Int(y), w: Int(w), h: Int(h), fit: encaixa != 0) }
}

@_cdecl("nvp_escolher")
func nvp_escolher(_ tipo: Int32, _ valor: Int32) {
    onMain { NvPlayer.shared.choose(kind: Int(tipo), value: Int(valor)) }
}

@_cdecl("nvp_velocidade")
func nvp_velocidade(_ c: Int32) { onMain { NvPlayer.shared.speed(Int(c)) } }

@_cdecl("nvp_bombear")
func nvp_bombear() { onMain { NvPlayer.shared.pump() } }
