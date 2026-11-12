import Foundation
import CSQLite

// Confined to Organizer's actor. Each journal entry commits before a filesystem mutation.
final class Database {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
            sqlite3_close(handle); handle = nil
            throw SortlaneError.database(message)
        }
        sqlite3_busy_timeout(handle, 5000)
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value BLOB NOT NULL); CREATE TABLE IF NOT EXISTS operations (id TEXT PRIMARY KEY, created REAL NOT NULL, value BLOB NOT NULL);")
    }
    deinit { sqlite3_close(handle) }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> SortlaneError { .database(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Database unavailable") }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &result, nil) == SQLITE_OK, let result else { throw failure() }
        return result
    }
    private func bind(_ text: String, to statement: OpaquePointer, at index: Int32) {
        _ = text.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
    }
    private func bind(_ data: Data, to statement: OpaquePointer, at index: Int32) {
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
    }
    private func data(_ statement: OpaquePointer, at index: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard let bytes = sqlite3_column_blob(statement, index), count > 0 else { return Data() }
        return Data(bytes: bytes, count: count)
    }
    func saveSetting(_ data: Data, key: String) throws {
        let stmt = try statement("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
        defer { sqlite3_finalize(stmt) }
        bind(key, to: stmt, at: 1); bind(data, to: stmt, at: 2)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    func setting(key: String) throws -> Data? {
        let stmt = try statement("SELECT value FROM settings WHERE key=?")
        defer { sqlite3_finalize(stmt) }
        bind(key, to: stmt, at: 1)
        switch sqlite3_step(stmt) {
        case SQLITE_ROW: return data(stmt, at: 0)
        case SQLITE_DONE: return nil
        default: throw failure()
        }
    }
    func save(_ operation: MoveOperation) throws {
        let stmt = try statement("INSERT INTO operations(id,created,value) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value")
        defer { sqlite3_finalize(stmt) }
        bind(operation.id.uuidString, to: stmt, at: 1)
        sqlite3_bind_double(stmt, 2, operation.createdAt.timeIntervalSince1970)
        bind(try JSONEncoder().encode(operation), to: stmt, at: 3)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    func operations() throws -> [MoveOperation] {
        let stmt = try statement("SELECT value FROM operations ORDER BY created DESC")
        defer { sqlite3_finalize(stmt) }
        var result: [MoveOperation] = []
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: result.append(try JSONDecoder().decode(MoveOperation.self, from: data(stmt, at: 0)))
            case SQLITE_DONE: return result
            default: throw failure()
            }
        }
    }
}
