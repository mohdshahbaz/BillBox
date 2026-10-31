import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

/// A row as the server returned it: column name -> Int / Double / String / NSNull.
public typealias Row = [String: Any]

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// An SQLite failure. `code` is the extended result code (SQLITE_CONSTRAINT_UNIQUE etc.).
public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { message }
    public var isConstraint: Bool { (code & 0xff) == SQLITE_CONSTRAINT }
}

/// The same small database API the Mac app's server used (backend/src/sqlite.js):
/// prepare().run / get / all, exec, pragma, transaction (nested = savepoints), close, read-only open.
public final class Database {
    public let path: String
    fileprivate var handle: OpaquePointer?
    private var depth = 0
    /// Compiled statements kept for reuse (the engine runs the same few hundred SQL texts over and over).
    fileprivate var cache: [String: OpaquePointer] = [:]
    fileprivate var busy: Set<String> = []

    public init(_ path: String, readonly: Bool = false) throws {
        self.path = path
        var h: OpaquePointer?
        let flags = readonly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let rc = sqlite3_open_v2(path, &h, flags | SQLITE_OPEN_NOMUTEX, nil)
        if rc != SQLITE_OK {
            let msg = h.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database"
            if let h { sqlite3_close_v2(h) }
            throw SQLiteError(code: rc, message: msg)
        }
        handle = h
        sqlite3_extended_result_codes(h, 1)
        sqlite3_busy_timeout(h, 5000)
    }

    deinit { close() }

    public func close() {
        for (_, st) in cache { sqlite3_finalize(st) }
        cache = [:]
        if let h = handle { sqlite3_close_v2(h); handle = nil }
    }

    /// A compiled statement for `sql`, reused when possible. `done` must be called after use.
    fileprivate func statement(_ sql: String) throws -> (OpaquePointer, cached: Bool) {
        guard let h = handle else { throw SQLiteError(code: SQLITE_MISUSE, message: "database is closed") }
        if !busy.contains(sql), let st = cache[sql] { busy.insert(sql); return (st, true) }
        var st: OpaquePointer?
        let rc = sqlite3_prepare_v2(h, sql, -1, &st, nil)
        guard rc == SQLITE_OK, let s = st else { throw error(rc) }
        if cache[sql] == nil && !busy.contains(sql) {
            if cache.count >= 512 { for (k, x) in cache where !busy.contains(k) { sqlite3_finalize(x); cache[k] = nil } }
            cache[sql] = s
            busy.insert(sql)
            return (s, true)
        }
        return (s, false)
    }

    fileprivate func done(_ sql: String, _ st: OpaquePointer, cached: Bool) {
        if cached {
            sqlite3_reset(st)
            sqlite3_clear_bindings(st)
            busy.remove(sql)
        } else {
            sqlite3_finalize(st)
        }
    }

    var isOpen: Bool { handle != nil }

    fileprivate func error(_ rc: Int32) -> SQLiteError {
        SQLiteError(code: handle.map { sqlite3_extended_errcode($0) } ?? rc,
                    message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "database is closed")
    }

    public func exec(_ sql: String) throws {
        guard let h = handle else { throw SQLiteError(code: SQLITE_MISUSE, message: "database is closed") }
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(h, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(h))
            sqlite3_free(err)
            throw SQLiteError(code: sqlite3_extended_errcode(h), message: msg)
        }
    }

    public func pragma(_ s: String) throws { try exec("PRAGMA " + s) }

    public func prepare(_ sql: String) -> Statement { Statement(self, sql) }

    /// Runs `body` inside BEGIN/COMMIT, or a SAVEPOINT when already inside a transaction. Any throw rolls back.
    @discardableResult
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        let nested = depth > 0
        let sp = "sp\(depth)"
        try exec(nested ? "SAVEPOINT \(sp)" : "BEGIN")
        depth += 1
        do {
            let r = try body()
            depth -= 1
            try exec(nested ? "RELEASE \(sp)" : "COMMIT")
            return r
        } catch {
            depth -= 1
            try? exec(nested ? "ROLLBACK TO \(sp); RELEASE \(sp)" : "ROLLBACK")
            throw error
        }
    }
}

public struct RunResult {
    public let changes: Int
    public let lastInsertRowid: Int
}

/// A prepared statement in the better-sqlite3 style. Arguments are positional (`?`) or one dictionary for named
/// parameters (`@name`, `:name`, `$name`); keys the SQL does not use are ignored, exactly like the Mac server.
public final class Statement {
    private let db: Database
    private let sql: String

    init(_ db: Database, _ sql: String) {
        self.db = db
        self.sql = sql
    }

    private func withStatement<T>(_ args: [Any?], _ body: (OpaquePointer) throws -> T) throws -> T {
        let (s, cached) = try db.statement(sql)
        defer { db.done(sql, s, cached: cached) }
        try bind(s, args)
        return try body(s)
    }

    private func bind(_ s: OpaquePointer, _ args: [Any?]) throws {
        let count = sqlite3_bind_parameter_count(s)
        if args.count == 1, let named = args[0] as? [String: Any?] {
            for i in 1...max(1, count) where i <= count {
                guard let cname = sqlite3_bind_parameter_name(s, i) else { continue }
                var name = String(cString: cname)
                name.removeFirst()
                if let v = named[name] { try bindValue(s, i, v) } else { try bindValue(s, i, nil) }
            }
            return
        }
        if args.count == 1, let named = args[0] as? [String: Any] {
            for i in 1...max(1, count) where i <= count {
                guard let cname = sqlite3_bind_parameter_name(s, i) else { continue }
                var name = String(cString: cname)
                name.removeFirst()
                try bindValue(s, i, named[name])
            }
            return
        }
        for (i, a) in args.enumerated() where Int32(i) < count {
            try bindValue(s, Int32(i + 1), a)
        }
    }

    private func bindValue(_ s: OpaquePointer, _ i: Int32, _ v: Any?) throws {
        var rc: Int32 = SQLITE_OK
        switch unwrap(v) {
        case nil: rc = sqlite3_bind_null(s, i)
        // node:sqlite binds every JavaScript number as a REAL; doing the same keeps every stored value identical
        // (an INTEGER column still stores 7, a TEXT column would store "7.0" exactly as on the Mac).
        case let x as Int: rc = sqlite3_bind_double(s, i, Double(x))
        case let x as Int64: rc = sqlite3_bind_double(s, i, Double(x))
        case let x as Int32: rc = sqlite3_bind_double(s, i, Double(x))
        case let x as Bool: rc = sqlite3_bind_int64(s, i, x ? 1 : 0)
        case let x as Double: rc = sqlite3_bind_double(s, i, x)
        case let x as String: rc = sqlite3_bind_text(s, i, x, -1, SQLITE_TRANSIENT)
        case let x as Data:
            rc = x.withUnsafeBytes { p in sqlite3_bind_blob(s, i, p.baseAddress, Int32(x.count), SQLITE_TRANSIENT) }
        case let x as NSNumber: rc = sqlite3_bind_double(s, i, x.doubleValue)
        default: rc = sqlite3_bind_text(s, i, "\(v!)", -1, SQLITE_TRANSIENT)
        }
        if rc != SQLITE_OK { throw db.error(rc) }
    }

    private func readRow(_ s: OpaquePointer) -> Row {
        var row: Row = [:]
        let n = sqlite3_column_count(s)
        for c in 0..<n {
            let name = String(cString: sqlite3_column_name(s, c))
            switch sqlite3_column_type(s, c) {
            case SQLITE_INTEGER: row[name] = Int(sqlite3_column_int64(s, c))
            case SQLITE_FLOAT: row[name] = sqlite3_column_double(s, c)
            case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(s, c))
            case SQLITE_BLOB:
                let len = Int(sqlite3_column_bytes(s, c))
                if let p = sqlite3_column_blob(s, c) { row[name] = Data(bytes: p, count: len) } else { row[name] = Data() }
            default: row[name] = NSNull()
            }
        }
        return row
    }

    /// `run` with the arguments in an array.
    @discardableResult
    public func runArgs(_ args: [Any?]) throws -> RunResult {
        try withStatement(args) { s in
            var rc = sqlite3_step(s)
            while rc == SQLITE_ROW { rc = sqlite3_step(s) }
            if rc != SQLITE_DONE { throw db.error(rc) }
            return RunResult(changes: Int(sqlite3_changes(db.handle)), lastInsertRowid: Int(sqlite3_last_insert_rowid(db.handle)))
        }
    }

    @discardableResult
    public func run(_ args: Any?...) throws -> RunResult {
        try withStatement(args) { s in
            var rc = sqlite3_step(s)
            while rc == SQLITE_ROW { rc = sqlite3_step(s) }
            if rc != SQLITE_DONE { throw db.error(rc) }
            return RunResult(changes: Int(sqlite3_changes(db.handle)), lastInsertRowid: Int(sqlite3_last_insert_rowid(db.handle)))
        }
    }

    public func get(_ args: Any?...) throws -> Row? {
        try withStatement(args) { s in
            let rc = sqlite3_step(s)
            if rc == SQLITE_ROW { return readRow(s) }
            if rc != SQLITE_DONE { throw db.error(rc) }
            return nil
        }
    }

    public func all(_ args: Any?...) throws -> [Row] {
        try withStatement(args) { s in
            var out: [Row] = []
            var rc = sqlite3_step(s)
            while rc == SQLITE_ROW {
                out.append(readRow(s))
                rc = sqlite3_step(s)
            }
            if rc != SQLITE_DONE { throw db.error(rc) }
            return out
        }
    }
}

/// Optional / NSNull flattening for values coming out of dictionaries.
func unwrap(_ v: Any?) -> Any? {
    guard let v else { return nil }
    if v is NSNull { return nil }
    let m = Mirror(reflecting: v)
    if m.displayStyle == .optional {
        if let first = m.children.first { return unwrap(first.value) }
        return nil
    }
    return v
}
