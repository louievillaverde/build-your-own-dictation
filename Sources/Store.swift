import Foundation
import SQLite3

struct Dictation: Identifiable {
    let id: String
    let createdAt: Date
    let appName: String
    let duration: Double
    let raw: String
    let text: String
    let engine: String
    let latencyMs: Int
    let pasted: Bool
    let audioPath: String?
}

/// SQLite history plus a daily Markdown archive. Everything is written before anything is pasted.
final class Store {
    static let shared = Store()
    private var db: OpaquePointer?
    private let q = DispatchQueue(label: "dictate.store")
    private let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        Config.ensureDirs()
        sqlite3_open(Config.dbPath, &db)
        exec("""
        CREATE TABLE IF NOT EXISTS dictations(
          id TEXT PRIMARY KEY, created_at REAL NOT NULL, app_id TEXT, app_name TEXT,
          duration REAL, raw TEXT, text TEXT, engine TEXT, latency_ms INTEGER,
          pasted INTEGER, audio_path TEXT, source TEXT DEFAULT 'dictate');
        CREATE INDEX IF NOT EXISTS idx_created ON dictations(created_at);
        """)
        // Added later; ALTER fails harmlessly once the column exists.
        exec("ALTER TABLE dictations ADD COLUMN edited INTEGER DEFAULT 0")
    }

    private func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }

    func insert(id: String, at: Date, appId: String, appName: String, duration: Double,
                raw: String, text: String, engine: String, latencyMs: Int, pasted: Bool, audioPath: String?) {
        q.sync {
            var st: OpaquePointer?
            sqlite3_prepare_v2(db, """
              INSERT OR REPLACE INTO dictations(id,created_at,app_id,app_name,duration,raw,text,engine,latency_ms,pasted,audio_path)
              VALUES(?,?,?,?,?,?,?,?,?,?,?)
            """, -1, &st, nil)
            sqlite3_bind_text(st, 1, id, -1, TRANSIENT)
            sqlite3_bind_double(st, 2, at.timeIntervalSince1970)
            sqlite3_bind_text(st, 3, appId, -1, TRANSIENT)
            sqlite3_bind_text(st, 4, appName, -1, TRANSIENT)
            sqlite3_bind_double(st, 5, duration)
            sqlite3_bind_text(st, 6, raw, -1, TRANSIENT)
            sqlite3_bind_text(st, 7, text, -1, TRANSIENT)
            sqlite3_bind_text(st, 8, engine, -1, TRANSIENT)
            sqlite3_bind_int(st, 9, Int32(latencyMs))
            sqlite3_bind_int(st, 10, pasted ? 1 : 0)
            if let a = audioPath { sqlite3_bind_text(st, 11, a, -1, TRANSIENT) } else { sqlite3_bind_null(st, 11) }
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
        appendMarkdown(at: at, appName: appName, duration: duration, text: text)
    }

    /// Saves a correction from History. Counted, because "how often do I fix it" is the quality metric.
    func updateText(_ id: String, _ text: String) {
        q.sync {
            var st: OpaquePointer?
            sqlite3_prepare_v2(db, "UPDATE dictations SET text=?, edited=edited+1 WHERE id=?", -1, &st, nil)
            sqlite3_bind_text(st, 1, text, -1, TRANSIENT)
            sqlite3_bind_text(st, 2, id, -1, TRANSIENT)
            sqlite3_step(st); sqlite3_finalize(st)
        }
    }

    func setPasted(_ id: String, _ pasted: Bool) {
        q.sync { exec("UPDATE dictations SET pasted=\(pasted ? 1 : 0) WHERE id='\(id)'") }
    }

    func setAudioPath(_ id: String, _ path: String) {
        q.sync {
            var st: OpaquePointer?
            sqlite3_prepare_v2(db, "UPDATE dictations SET audio_path=? WHERE id=?", -1, &st, nil)
            sqlite3_bind_text(st, 1, path, -1, TRANSIENT)
            sqlite3_bind_text(st, 2, id, -1, TRANSIENT)
            sqlite3_step(st); sqlite3_finalize(st)
        }
    }

    func recent(search: String = "", limit: Int = 500) -> [Dictation] {
        q.sync {
            var st: OpaquePointer?
            let sql = search.isEmpty
                ? "SELECT id,created_at,app_name,duration,raw,text,engine,latency_ms,pasted,audio_path FROM dictations ORDER BY created_at DESC LIMIT ?"
                : "SELECT id,created_at,app_name,duration,raw,text,engine,latency_ms,pasted,audio_path FROM dictations WHERE text LIKE ? OR raw LIKE ? ORDER BY created_at DESC LIMIT ?"
            sqlite3_prepare_v2(db, sql, -1, &st, nil)
            if search.isEmpty {
                sqlite3_bind_int(st, 1, Int32(limit))
            } else {
                let like = "%\(search)%"
                sqlite3_bind_text(st, 1, like, -1, TRANSIENT)
                sqlite3_bind_text(st, 2, like, -1, TRANSIENT)
                sqlite3_bind_int(st, 3, Int32(limit))
            }
            var out: [Dictation] = []
            func s(_ i: Int32) -> String { sqlite3_column_text(st, i).map { String(cString: $0) } ?? "" }
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(Dictation(
                    id: s(0), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 1)),
                    appName: s(2), duration: sqlite3_column_double(st, 3), raw: s(4), text: s(5),
                    engine: s(6), latencyMs: Int(sqlite3_column_int(st, 7)), pasted: sqlite3_column_int(st, 8) == 1,
                    audioPath: sqlite3_column_type(st, 9) == SQLITE_NULL ? nil : s(9)))
            }
            sqlite3_finalize(st)
            return out
        }
    }

    func last() -> Dictation? { recent(limit: 1).first }

    private func appendMarkdown(at: Date, appName: String, duration: Double, text: String) {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter(); tf.dateFormat = "h:mm a"
        let url = Config.daysDir.appendingPathComponent("\(df.string(from: at)).md")
        var entry = "## \(tf.string(from: at)) · \(appName) · \(Int(duration.rounded()))s\n\n\(text)\n\n"
        if !FileManager.default.fileExists(atPath: url.path) {
            entry = "# Dictations \(df.string(from: at))\n\n" + entry
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(entry.data(using: .utf8)!); try? h.close()
        }
    }
}
