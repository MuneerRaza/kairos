import AppKit
import Observation

enum YouTube {
    /// The 11-character video id in a youtube.com or youtu.be link, if the text is one.
    static func videoID(in text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.contains(where: \.isWhitespace),
              let parts = URLComponents(string: text),
              parts.scheme == "https" || parts.scheme == "http",
              let host = parts.host?.lowercased() else { return nil }

        let path = parts.path.split(separator: "/").map(String.init)
        var id: String?
        if host == "youtu.be" {
            id = path.first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if path.first == "watch" {
                id = parts.queryItems?.first { $0.name == "v" }?.value
            } else if path.count > 1, ["shorts", "embed", "live", "v"].contains(path[0]) {
                id = path[1]
            }
        }
        guard let id, id.count == 11,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return id
    }

    static func thumbnailURL(_ id: String, large: Bool = false) -> URL {
        URL(string: "https://i.ytimg.com/vi/\(id)/\(large ? "maxresdefault" : "mqdefault").jpg")!
    }
}

/// Thumbnails and titles for YouTube links, fetched once per app run.
/// Kairos stays open in the background, so memory is enough of a cache.
@MainActor
@Observable
final class LinkPreviews {
    struct Info { var title: String; var channel: String? }

    static let shared = LinkPreviews()

    private(set) var thumbnails: [String: NSImage] = [:]
    private(set) var info: [String: Info] = [:]
    @ObservationIgnored private var loading: Set<String> = []

    func load(_ id: String) {
        guard thumbnails[id] == nil, loading.insert(id).inserted else { return }
        Task {
            async let image = Self.fetch(YouTube.thumbnailURL(id))
            async let meta = Self.fetch(URL(string: "https://www.youtube.com/oembed?format=json&url=https://youtu.be/\(id)")!)

            if let data = await image, let picture = NSImage(data: data) { thumbnails[id] = picture }
            if let data = await meta,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let title = json["title"] as? String {
                info[id] = Info(title: title, channel: json["author_name"] as? String)
            }
            // Offline or blocked: try again next time the row shows.
            loading.remove(id)
        }
    }

    private nonisolated static func fetch(_ url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
