import Foundation

/// "attach the last two screenshots" → the real file paths, newest first.
/// Desktop by default (where screenshots land); "from downloads" for AirDrops from the phone.
enum Attachments {
    struct Request { let count: Int; let downloads: Bool; let recording: Bool }

    private static let pattern = #"(?i)\b(?:attach|add|include)\s+(?:the\s+|my\s+)?(?:last|latest|newest|most recent)?\s*(one|two|three|four|five|a couple(?: of)?|\d)?\s*(?:screen\s?shots?|screen\s?recordings?|recordings?|photos?|pictures?|images?)(?:\s+(?:from|in)\s+(?:my\s+|the\s+)?downloads?)?[.,]?"#

    static func request(in text: String) -> Request? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(m.range, in: text) else { return nil }
        let phrase = text[whole].lowercased()
        var n = 1
        if let r = Range(m.range(at: 1), in: text) {
            let w = text[r].lowercased()
            n = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5][w] ?? (w.hasPrefix("a couple") ? 2 : Int(w) ?? 1)
        } else if phrase.contains("screenshots") || phrase.contains("recordings") || phrase.contains("photos") || phrase.contains("images") || phrase.contains("pictures") {
            n = 2 // plural with no number, e.g. "attach the screenshots"
        }
        return Request(count: min(n, 10), downloads: phrase.contains("download"),
                       recording: phrase.contains("recording"))
    }

    /// Removes the spoken request from the (possibly polished) text and appends the paths.
    static func expand(_ text: String, raw: String) -> (String, [String]) {
        guard let req = request(in: raw) ?? request(in: text) else { return (text, []) }
        let files = newest(req).map(stableCopy)
        guard !files.isEmpty else { return (text, []) }
        var body = text
        if let re = try? NSRegularExpression(pattern: pattern) {
            body = re.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body), withTemplate: "")
        }
        body = body.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let quoted = files.map { "\"\($0)\"" }.joined(separator: " ")
        return (body.isEmpty ? quoted : body + "\n" + quoted, files)
    }

    /// macOS screenshot names put a narrow no-break space (U+202F) before AM/PM. Pasted into a terminal it
    /// becomes a normal space and the path no longer resolves, so hand over a copy at a plain path instead.
    static func stableCopy(_ path: String) -> String {
        let src = URL(fileURLWithPath: path)
        let dir = Config.daysDir.appendingPathComponent("attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let created = (try? src.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HHmmss"
        var dest = dir.appendingPathComponent("\(f.string(from: created)).\(src.pathExtension.lowercased())")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            if FileManager.default.contentsEqual(atPath: dest.path, andPath: path) { return dest.path }
            dest = dir.appendingPathComponent("\(f.string(from: created))-\(n).\(src.pathExtension.lowercased())"); n += 1
        }
        return (try? FileManager.default.copyItem(at: src, to: dest)) != nil ? dest.path : path
    }

    static func newest(_ req: Request) -> [String] {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(req.downloads ? "Downloads" : "Desktop")
        let images: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff"]
        let videos: Set<String> = ["mov", "mp4", "m4v"]
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                      options: [.skipsHiddenFiles]) else { return [] }
        return urls
            .filter { u in
                let ext = u.pathExtension.lowercased()
                if req.recording { return videos.contains(ext) }
                guard images.contains(ext) else { return false }
                // On the Desktop, only real screenshots; in Downloads, any image (AirDrops are IMG_xxxx).
                return req.downloads || u.lastPathComponent.hasPrefix("Screenshot") || u.lastPathComponent.hasPrefix("Screen Shot")
            }
            .map { u in (u, (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .prefix(req.count)
            .map { $0.0.path }
    }
}
