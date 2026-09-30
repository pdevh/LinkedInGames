import Foundation
import SQLite3
import CryptoKit

/// One writer owns the connection. Acknowledgment never deletes the source event.
final class DifficultyJournal {
    struct Pending: Codable {
        let eventID: String
        let sequence: Int64
        let payload: String
        let sha256: String
    }
    enum Failure: Error { case database(String), invalidReceipt }
    private let writer = DispatchQueue(label: "difficulty.journal")
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw Failure.database("Cannot open journal")
        }
        sqlite3_busy_timeout(db, 5000)
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;")
        try execute("""
        CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        INSERT OR IGNORE INTO metadata VALUES('sequence','0');
        CREATE TABLE IF NOT EXISTS events(
          event_id TEXT PRIMARY KEY, sequence INTEGER UNIQUE NOT NULL,
          payload TEXT NOT NULL, sha256 TEXT NOT NULL, created_at REAL NOT NULL,
          acknowledged_at REAL, quarantine TEXT);
        CREATE TABLE IF NOT EXISTS outbox(
          event_id TEXT PRIMARY KEY REFERENCES events(event_id), attempts INTEGER NOT NULL DEFAULT 0,
          next_attempt REAL NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS terminals(
          serve_id TEXT PRIMARY KEY, game TEXT NOT NULL, snapshot BLOB NOT NULL,
          event_id TEXT NOT NULL REFERENCES events(event_id));
        PRAGMA user_version=1;
        """)
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }
    private func error() -> Failure { .database(String(cString: sqlite3_errmsg(db))) }
    private func statement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        var p: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &p, nil) == SQLITE_OK, let p else { throw error() }
        defer { sqlite3_finalize(p) }
        try body(p)
    }
    private func bind(_ s: String, _ index: Int32, _ p: OpaquePointer) {
        sqlite3_bind_text(p, index, s, -1, transient)
    }
    private func done(_ p: OpaquePointer) throws {
        guard sqlite3_step(p) == SQLITE_DONE else { throw error() }
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let value = try body(); try execute("COMMIT"); return value }
        catch { try? execute("ROLLBACK"); throw error }
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Encoding receives the sequence allocated in this same transaction. Terminal retries
    /// return their existing event, so crash reconciliation cannot invent a second terminal.
    @discardableResult
    func append(eventID: UUID = UUID(), terminal: (serveID: UUID, game: String, snapshot: Data)? = nil,
                encode: (Int64, UUID) throws -> Data) throws -> String {
        try writer.sync { try transaction {
            if let terminal {
                var existing: String?
                try statement("SELECT event_id FROM terminals WHERE serve_id=?") { p in
                    bind(terminal.serveID.uuidString, 1, p)
                    if sqlite3_step(p) == SQLITE_ROW { existing = String(cString: sqlite3_column_text(p, 0)) }
                }
                if let existing { return existing }
            }
            var sequence: Int64 = 0
            try statement("SELECT CAST(value AS INTEGER)+1 FROM metadata WHERE key='sequence'") { p in
                guard sqlite3_step(p) == SQLITE_ROW else { throw error() }
                sequence = sqlite3_column_int64(p, 0)
            }
            let data = try encode(sequence, eventID)
            guard let payload = String(data: data, encoding: .utf8) else { throw Failure.database("Invalid UTF8") }
            try statement("INSERT INTO events(event_id,sequence,payload,sha256,created_at) VALUES(?,?,?,?,?)") { p in
                bind(eventID.uuidString, 1, p); sqlite3_bind_int64(p, 2, sequence)
                bind(payload, 3, p); bind(Self.hash(data), 4, p)
                sqlite3_bind_double(p, 5, Date().timeIntervalSince1970); try done(p)
            }
            try statement("INSERT INTO outbox(event_id) VALUES(?)") { p in bind(eventID.uuidString, 1, p); try done(p) }
            try statement("UPDATE metadata SET value=? WHERE key='sequence'") { p in bind(String(sequence), 1, p); try done(p) }
            if let terminal {
                try statement("INSERT INTO terminals VALUES(?,?,?,?)") { p in
                    bind(terminal.serveID.uuidString, 1, p); bind(terminal.game, 2, p)
                    _ = terminal.snapshot.withUnsafeBytes { sqlite3_bind_blob(p, 3, $0.baseAddress, Int32($0.count), transient) }
                    bind(eventID.uuidString, 4, p); try done(p)
                }
            }
            return eventID.uuidString
        } }
    }
    func pending(limit: Int = 500, now: Date = Date()) throws -> [Pending] {
        try writer.sync {
            var rows: [Pending] = []
            try statement("SELECT e.event_id,e.sequence,e.payload,e.sha256 FROM events e JOIN outbox o USING(event_id) WHERE e.quarantine IS NULL AND o.next_attempt<=? ORDER BY e.sequence LIMIT ?") { p in
                sqlite3_bind_double(p, 1, now.timeIntervalSince1970); sqlite3_bind_int(p, 2, Int32(min(500,max(1,limit))))
                while sqlite3_step(p) == SQLITE_ROW {
                    rows.append(Pending(eventID: String(cString: sqlite3_column_text(p,0)), sequence: sqlite3_column_int64(p,1),
                                        payload: String(cString: sqlite3_column_text(p,2)), sha256: String(cString: sqlite3_column_text(p,3))))
                }
            }
            return rows
        }
    }
    func acknowledge(_ receipts: [(eventID: String, sha256: String)]) throws {
        try writer.sync { try transaction {
            for receipt in receipts {
                var matches = false
                try statement("SELECT 1 FROM events WHERE event_id=? AND sha256=?") { p in
                    bind(receipt.eventID,1,p); bind(receipt.sha256,2,p); matches = sqlite3_step(p) == SQLITE_ROW
                }
                guard matches else { throw Failure.invalidReceipt }
                try statement("UPDATE events SET acknowledged_at=? WHERE event_id=?") { p in
                    sqlite3_bind_double(p,1,Date().timeIntervalSince1970); bind(receipt.eventID,2,p); try done(p)
                }
                try statement("DELETE FROM outbox WHERE event_id=?") { p in bind(receipt.eventID,1,p); try done(p) }
            }
        } }
    }
    func retry(_ ids: [String], after: Date, quarantine: String? = nil) throws {
        try writer.sync { try transaction {
            for id in ids {
                try statement("UPDATE outbox SET attempts=attempts+1,next_attempt=? WHERE event_id=?") { p in
                    sqlite3_bind_double(p,1,after.timeIntervalSince1970); bind(id,2,p); try done(p)
                }
                if let quarantine {
                    try statement("UPDATE events SET quarantine=? WHERE event_id=?") { p in bind(quarantine,1,p); bind(id,2,p); try done(p) }
                }
            }
        } }
    }
    func terminalSnapshots() throws -> [(game: String, data: Data)] {
        try writer.sync {
            var result: [(String,Data)] = []
            try statement("SELECT game,snapshot FROM terminals ORDER BY rowid") { p in
                while sqlite3_step(p) == SQLITE_ROW {
                    result.append((String(cString: sqlite3_column_text(p,0)), Data(bytes: sqlite3_column_blob(p,1), count: Int(sqlite3_column_bytes(p,1)))))
                }
            }
            return result
        }
    }
}
