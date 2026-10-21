// Nuvio Legacy on Apple TV: the Top Shelf. With the app's icon in the top row
// of the Apple TV home screen, its Continue Watching sits above the icons, as
// in the TV app or Netflix.
//
// The app writes the row (NvTopShelf.m, from the core's Continue Watching) to
// the shared app group container as one tab separated line per title:
//   imdb  type  season  episode  progress%  title  subtitle  image URL
// Selecting a title opens it in the app (dexlegacy://titulo/<imdb>). Without
// the app group (a signing tool that drops it) the file is never found and
// tvOS shows the app's static top shelf image instead.
import Foundation
import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    static let group = "group.cc.dexworld.dexlegacy"

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.group),
              let text = try? String(contentsOf: dir.appendingPathComponent("TopShelf/continue.txt"), encoding: .utf8)
        else { completionHandler(nil); return }
        var items: [TVTopShelfSectionedItem] = []
        for line in text.split(separator: "\n").prefix(12) {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 8, !f[0].isEmpty, !f[5].isEmpty else { continue }
            let item = TVTopShelfSectionedItem(identifier: f[0] + ":" + f[2] + ":" + f[3])
            item.title = f[6].isEmpty ? f[5] : f[5] + " · " + f[6]
            item.imageShape = .hdtv
            if let url = URL(string: f[7]), url.scheme?.hasPrefix("http") == true {
                item.setImageURL(url, for: .screenScale1x)
                item.setImageURL(url, for: .screenScale2x)
            }
            if let p = Double(f[4]), p > 0 { item.playbackProgress = min(1, p / 100) }
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/")
            let id = f[0].addingPercentEncoding(withAllowedCharacters: allowed) ?? f[0]
            if let open = URL(string: "dexlegacy://titulo/" + id) {
                item.displayAction = TVTopShelfAction(url: open)
                item.playAction = TVTopShelfAction(url: open)
            }
            items.append(item)
        }
        guard !items.isEmpty else { completionHandler(nil); return }
        let section = TVTopShelfItemCollection(items: items)
        section.title = Locale.preferredLanguages.first?.hasPrefix("ar") == true ? "متابعة المشاهدة" : "Continue Watching"
        completionHandler(TVTopShelfSectionedContent(sections: [section]))
    }
}
