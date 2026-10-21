// Test-only remote control for the simulator: reads command files that the
// Mac-side job drops into $NV_REMOTE_DIR/cmd (default <repo>/.remote/cmd)
// and plays them on the Siri Remote, so the app can be driven headless.
//   press up|down|left|right|select|menu|playpause|home [count]
//   hold select <seconds>
//   wait <seconds>
//   shot <name>          -> shots/<name>.png
//   quit
import XCTest

final class RemoteDriver: XCTestCase {
    func testDrive() throws {
        let app = XCUIApplication(bundleIdentifier: "cc.dexworld.dexlegacy")
        app.activate()
        // remote-start.sh passes TEST_RUNNER_NV_REMOTE_DIR, seen here as NV_REMOTE_DIR.
        let env = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: env["NV_REMOTE_DIR"]
            ?? ((env["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()) + "/dex-legacy-remote"))
        let cmdDir = root.appendingPathComponent("cmd")
        let shots = root.appendingPathComponent("shots")
        let fm = FileManager.default
        try? fm.createDirectory(at: cmdDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: shots, withIntermediateDirectories: true)
        let remote = XCUIRemote.shared
        let deadline = Date().addingTimeInterval(4 * 3600)

        while Date() < deadline {
            let files = ((try? fm.contentsOfDirectory(atPath: cmdDir.path)) ?? [])
                .filter { $0.hasSuffix(".txt") }.sorted()
            guard let name = files.first else { Thread.sleep(forTimeInterval: 0.5); continue }
            let file = cmdDir.appendingPathComponent(name)
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            try? fm.moveItem(at: file, to: file.appendingPathExtension("done"))
            for raw in text.split(separator: "\n") {
                let p = raw.split(separator: " ").map(String.init)
                guard let op = p.first else { continue }
                switch op {
                case "press":
                    let n = p.count > 2 ? Int(p[2]) ?? 1 : 1
                    let b: XCUIRemote.Button
                    switch p.count > 1 ? p[1] : "" {
                    case "up": b = .up
                    case "down": b = .down
                    case "left": b = .left
                    case "right": b = .right
                    case "menu": b = .menu
                    case "playpause": b = .playPause
                    case "home": b = .home
                    default: b = .select
                    }
                    for _ in 0..<n { remote.press(b); Thread.sleep(forTimeInterval: 0.35) }
                case "hold":
                    remote.press(.select, forDuration: Double(p.count > 2 ? p[2] : "1") ?? 1)
                case "wait":
                    Thread.sleep(forTimeInterval: Double(p.count > 1 ? p[1] : "1") ?? 1)
                case "shot":
                    let png = XCUIScreen.main.screenshot().pngRepresentation
                    try? png.write(to: shots.appendingPathComponent((p.count > 1 ? p[1] : "shot") + ".png"))
                case "quit":
                    return
                default:
                    break
                }
            }
        }
    }
}
