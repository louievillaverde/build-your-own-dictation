import Foundation

enum Config {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let support = home.appendingPathComponent("Library/Application Support/Dictation")
    static let audioDir = support.appendingPathComponent("audio")
    static let dbPath = support.appendingPathComponent("dictate.sqlite").path
    static let vocabPath = support.appendingPathComponent("vocab.txt")
    static let snippetsPath = support.appendingPathComponent("snippets.tsv")
    /// Human-readable archive, one Markdown file per day.
    static let daysDir = home.appendingPathComponent("Dictations")
    static let secretsPath = home.appendingPathComponent(".dictation-secrets.env")
    static let learnedVocabPath = support.appendingPathComponent("vocab-learned.txt")

    static let sampleRate: Double = 16_000
    static let scribeModel = "scribe_v2"
    static let cleanupModel = "claude-haiku-4-5-20251001"
    /// Cut a chunk and upload it once this much audio has built up and the speaker pauses.
    static let chunkMinSeconds: Double = 20
    static let chunkPauseSeconds: Double = 0.35

    /// Apps where the transcript goes straight in (fillers stripped, no LLM pass).
    static let rawApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
        "com.anthropic.claudefordesktop", "dev.zed.Zed",
    ]
    static let casualApps: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "net.whatsapp.WhatsApp",
        "com.hnc.Discord", "ru.keepcoder.Telegram",
    ]
    static let emailApps: Set<String> = [
        "com.apple.mail", "com.readdle.smartemail-Mac", "com.superhuman.electron",
    ]

    static func ensureDirs() {
        for d in [support, audioDir, daysDir] {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    /// Saves a key to ~/.dictation-secrets.env (replacing any old value), so engines can be
    /// plugged in from Settings without editing files. An empty value removes the key.
    static func setSecret(_ name: String, _ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ((try? String(contentsOf: secretsPath, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.removeAll { l in
            var t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("export ") { t.removeFirst(7) }
            return t.hasPrefix(name + "=")
        }
        while lines.last == "" { lines.removeLast() }
        if !v.isEmpty { lines.append("export \(name)=\(v)") }
        try? (lines.joined(separator: "\n") + "\n").write(to: secretsPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsPath.path)
    }

    static func secret(_ name: String) -> String? {
        if let v = ProcessInfo.processInfo.environment[name], !v.isEmpty { return v }
        let s = [secretsPath].compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        for line in s.split(separator: "\n") {
            var l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("export ") { l.removeFirst(7) }
            let parts = l.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == name {
                return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
        }
        return nil
    }

    /// One term per line; `#` comments allowed. Sent to the transcriber as keyterms and to Haiku as spelling hints.
    /// Hand-edited terms first, then ones learned from corrections.
    static func vocab() -> [String] {
        var seen = Set<String>()
        return [vocabPath, learnedVocabPath]
            .flatMap { parseVocab((try? String(contentsOf: $0, encoding: .utf8)) ?? "") }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    static func learn(_ words: [String]) {
        let have = Set(vocab().map { $0.lowercased() })
        let new = words.filter { !have.contains($0.lowercased()) }
        guard !new.isEmpty else { return }
        let existing = (try? String(contentsOf: learnedVocabPath, encoding: .utf8)) ?? "# Learned from your corrections in History.\n"
        try? (existing + new.joined(separator: "\n") + "\n").write(to: learnedVocabPath, atomically: true, encoding: .utf8)
        debugLog("learned vocab: \(new)")
    }

    static func parseVocab(_ s: String) -> [String] {
        s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// `spoken phrase<TAB>replacement` per line.
    static func snippets() -> [(String, String)] {
        guard let s = try? String(contentsOf: snippetsPath, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return p.count == 2 && !p[0].hasPrefix("#") ? (p[0], p[1]) : nil
        }
    }
}

/// Appends to ~/Library/Application Support/Dictation/debug.log (unified logging hides NSLog from dev builds).
func debugLog(_ msg: String) {
    let url = Config.support.appendingPathComponent("debug.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}
