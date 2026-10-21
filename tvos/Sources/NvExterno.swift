// Nuvio Legacy on Apple TV: hand a stream to another player app.
//
// URL formats come from NuvioTVOS (Models/PlayerModels.swift, ExternalPlayer),
// so Infuse, VLC, Outplayer, nPlayer, VidHub, SenPlayer and Native Player get
// exactly what they get from the NuvioTVOS build. The order matches the
// "Player de video" setting in ajustes.c (V_PLAYER_APPLE).
import UIKit

enum NvExternalPlayer: Int {
    case builtIn = 0, infuse, vlc, outplayer, nplayer, vidhub, senplayer, nativePlayer

    /// RFC 3986 unreserved only, so the target app sees the stream URL intact.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func enc(_ s: String) -> String? {
        s.addingPercentEncoding(withAllowedCharacters: unreserved)
    }

    func launchURL(stream: URL, title: String, position: Double, subtitles: [URL] = []) -> URL? {
        guard let e = Self.enc(stream.absoluteString) else { return nil }
        let name = title.isEmpty ? nil : Self.enc(title)
        let pos = position > 0 ? "&position=\(Int(position))" : ""
        let subs = subtitles.compactMap { Self.enc($0.absoluteString) }
        // Infuse / SenPlayer / Native Player take several sub=; VLC and VidHub one.
        let many = subs.prefix(8).map { "&sub=\($0)" }.joined()
        let one = subs.first.map { "&sub=\($0)" } ?? ""
        switch self {
        case .builtIn:
            return nil
        case .infuse:
            var q = "infuse://x-callback-url/play?url=\(e)"
            if let name { q += "&filename=\(name)" }
            return URL(string: q + pos + many)
        case .vlc:
            return URL(string: "vlc-x-callback://x-callback-url/stream?url=\(e)" + one)
        case .outplayer:
            if let name { return URL(string: "outplayer://x-callback-url/play?url=\(e)&filename=\(name)") }
            return URL(string: "outplayer://\(e)")
        case .nplayer:
            let s = stream.absoluteString
            if stream.scheme?.lowercased() == "https" {
                return URL(string: "nplayer-https://" + s.dropFirst("https://".count))
            }
            if stream.scheme?.lowercased() == "http" {
                return URL(string: "nplayer-http://" + s.dropFirst("http://".count))
            }
            return URL(string: "nplayer-\(e)")
        case .vidhub:
            var q = "vidhub://play?url=\(e)"
            if let name { q += "&filename=\(name)" }
            return URL(string: q + pos + one)
        case .senplayer:
            var q = "senplayer://x-callback-url/play?url=\(e)"
            if let name { q += "&filename=\(name)" }
            return URL(string: q + pos + many)
        case .nativePlayer:
            guard let scheme = stream.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  stream.pathExtension.lowercased() != "mpd" else { return nil }
            var q = "nativeplayer://play?url=\(e)" + pos
            if let name { q += "&name=\(name)" }
            return URL(string: q + many)
        }
    }
}

/// Scheme probe used before the core closes its player for a handoff.
@_cdecl("nv_tvos_player_instalado")
func nv_tvos_player_instalado(_ qual: Int32) -> Int32 {
    guard let p = NvExternalPlayer(rawValue: Int(qual)), p != .builtIn,
          let probe = p.launchURL(stream: URL(string: "https://example.com/v.mkv")!, title: "", position: 0)
    else { return 0 }
    return UIApplication.shared.canOpenURL(probe) ? 1 : 0
}

@_cdecl("nv_tvos_player_externo")
func nv_tvos_player_externo(_ qual: Int32, _ url: UnsafePointer<CChar>?, _ titulo: UnsafePointer<CChar>?,
                            _ posSeg: Double, _ legendas: UnsafePointer<CChar>?) -> Int32 {
    let subs = (legendas.map { String(cString: $0) } ?? "")
        .split(separator: "\n").compactMap { URL(string: String($0)) }
    guard let player = NvExternalPlayer(rawValue: Int(qual)), player != .builtIn,
          let url, let stream = URL(string: String(cString: url)) else { return 0 }
    let title = titulo.map { String(cString: $0) } ?? ""
    guard let target = player.launchURL(stream: stream, title: title, position: posSeg, subtitles: subs) else {
        NSLog("[tvos] externo: no URL for %@", "\(player)")
        return 0
    }
    // canOpenURL needs the scheme in LSApplicationQueriesSchemes (Info.plist).
    guard UIApplication.shared.canOpenURL(target) else {
        NSLog("[tvos] externo: %@ not installed, playing in-app", "\(player)")
        return 0
    }
    NSLog("[tvos] externo: handing off to %@ with %d subtitle(s)", "\(player)", subs.count)
    UIApplication.shared.open(target, options: [:], completionHandler: nil)
    return 1
}
