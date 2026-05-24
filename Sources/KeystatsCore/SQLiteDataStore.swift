import CSQLite
import Foundation

public enum DataStoreError: Error, CustomStringConvertible {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)
    case stepFailed(String)

    public var description: String {
        switch self {
        case .openFailed(let message): return "open failed: \(message)"
        case .prepareFailed(let message): return "prepare failed: \(message)"
        case .executeFailed(let message): return "execute failed: \(message)"
        case .stepFailed(let message): return "step failed: \(message)"
        }
    }
}

public final class SQLiteDataStore {
    private var db: OpaquePointer?
    private let path: String

    public init(path: String) throws {
        self.path = path
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        if sqlite3_open(path, &db) != SQLITE_OK {
            throw DataStoreError.openFailed(lastError)
        }

        try configure()
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    public func close() {
        sqlite3_close(db)
        db = nil
    }

    private var lastError: String {
        if let db {
            return String(cString: sqlite3_errmsg(db))
        }
        return "unknown sqlite error"
    }

    private func configure() throws {
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA busy_timeout = 5000;")
        try execute("PRAGMA foreign_keys = ON;")
    }

    private func migrate() throws {
        try execute(Self.schema)
        try execute(
            """
            INSERT OR IGNORE INTO schema_migrations(version, applied_at)
            VALUES(1, ?);
            """,
            [.text(DateUtils.isoString(Date()))]
        )
    }

    public func execute(_ sql: String, _ values: [SQLiteValue] = []) throws {
        if values.isEmpty {
            var errorMessage: UnsafeMutablePointer<Int8>?
            defer { sqlite3_free(errorMessage) }
            guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
                let message = errorMessage.map { String(cString: $0) } ?? lastError
                throw DataStoreError.executeFailed(message)
            }
            return
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DataStoreError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(statement) }

        try bind(values, to: statement)

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            guard result == SQLITE_ROW else {
                throw DataStoreError.executeFailed(lastError)
            }
        }
    }

    public func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func query(_ sql: String, _ values: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DataStoreError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(statement) }

        try bind(values, to: statement)

        var rows: [[String: SQLiteValue]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw DataStoreError.stepFailed(lastError)
            }

            var row: [String: SQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = SQLiteValue(statement: statement, index: index)
            }
            rows.append(row)
        }
        return rows
    }

    public func upsertMinuteStats(_ buckets: [MinuteBucket]) throws {
        guard !buckets.isEmpty else { return }
        try transaction {
            for bucket in buckets {
                try execute(
                    """
                    INSERT INTO minute_stats(
                        minute, app_bundle_id, app_name, total_keys, letters, numbers,
                        symbols, function_keys, modifier_keys
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(minute, app_bundle_id) DO UPDATE SET
                        app_name = excluded.app_name,
                        total_keys = total_keys + excluded.total_keys,
                        letters = letters + excluded.letters,
                        numbers = numbers + excluded.numbers,
                        symbols = symbols + excluded.symbols,
                        function_keys = function_keys + excluded.function_keys,
                        modifier_keys = modifier_keys + excluded.modifier_keys;
                    """,
                    [
                        .text(DateUtils.isoString(bucket.minute)),
                        .text(bucket.app.bundleID),
                        .text(bucket.app.name),
                        .int(bucket.totalKeys),
                        .int(bucket.letters),
                        .int(bucket.numbers),
                        .int(bucket.symbols),
                        .int(bucket.functionKeys),
                        .int(bucket.modifierKeys)
                    ]
                )
            }
        }
    }

    public func upsertKeyUsage(_ buckets: [KeyUsageBucket]) throws {
        guard !buckets.isEmpty else { return }
        try transaction {
            for bucket in buckets {
                try execute(
                    """
                    INSERT INTO key_usage_stats(
                        date, hour, app_bundle_id, app_name, key_code, key_name, key_category, count
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(date, hour, app_bundle_id, key_code) DO UPDATE SET
                        app_name = excluded.app_name,
                        key_name = excluded.key_name,
                        key_category = excluded.key_category,
                        count = count + excluded.count;
                    """,
                    [
                        .text(bucket.date),
                        .int(bucket.hour),
                        .text(bucket.app.bundleID),
                        .text(bucket.app.name),
                        .int(bucket.key.keyCode),
                        .text(bucket.key.keyName),
                        .text(bucket.key.category.rawValue),
                        .int(bucket.count)
                    ]
                )
            }
        }
    }

    public func insertKeyEvents(_ events: [CapturedKeyEvent]) throws {
        guard !events.isEmpty else { return }
        try transaction {
            for event in events {
                try execute(
                    """
                    INSERT INTO key_events(timestamp, key_code, key_name, key_category, app_bundle_id, app_name, modifiers)
                    VALUES (?, ?, ?, ?, ?, ?, ?);
                    """,
                    [
                        .text(DateUtils.isoString(event.timestamp)),
                        .int(event.key.keyCode),
                        .text(event.key.keyName),
                        .text(event.key.category.rawValue),
                        .text(event.app.bundleID),
                        .text(event.app.name),
                        .int(event.key.modifiers)
                    ]
                )
            }
        }
    }

    public func clearDetailEvents() throws {
        try execute("DELETE FROM key_events;")
    }

    public func clearAllData() throws {
        try execute("DELETE FROM key_events;")
        try execute("DELETE FROM key_usage_stats;")
        try execute("DELETE FROM minute_stats;")
        try execute("DELETE FROM daily_stats;")
    }

    public func deleteDetailEvents(olderThan cutoff: Date) throws {
        try execute("DELETE FROM key_events WHERE timestamp < ?;", [.text(DateUtils.isoString(cutoff))])
    }

    public func todayStats(on date: Date = Date()) throws -> TodayStats {
        let day = DateUtils.dayString(date)
        let start = "\(day)T00:00:00.000Z"
        let endDate = DateUtils.calendar.date(byAdding: .day, value: 1, to: DateUtils.calendar.startOfDay(for: date)) ?? date
        let end = DateUtils.isoString(endDate)

        let rows = try query(
            """
            SELECT
                COALESCE(SUM(total_keys), 0) AS total_keys,
                COALESCE(SUM(letters), 0) AS letters,
                COALESCE(SUM(numbers), 0) AS numbers,
                COALESCE(SUM(symbols), 0) AS symbols,
                COALESCE(SUM(function_keys), 0) AS function_keys,
                COALESCE(SUM(modifier_keys), 0) AS modifier_keys,
                COUNT(*) AS active_minutes
            FROM minute_stats
            WHERE minute >= ? AND minute < ?;
            """,
            [.text(start), .text(end)]
        )

        let row = rows.first ?? [:]
        let total = row["total_keys"]?.intValue ?? 0
        let distribution: [KeyCategory: Int] = [
            .letter: row["letters"]?.intValue ?? 0,
            .number: row["numbers"]?.intValue ?? 0,
            .symbol: row["symbols"]?.intValue ?? 0,
            .function: row["function_keys"]?.intValue ?? 0,
            .modifier: row["modifier_keys"]?.intValue ?? 0
        ]

        let topApp = try query(
            """
            SELECT app_name, SUM(total_keys) AS total
            FROM minute_stats
            WHERE minute >= ? AND minute < ?
            GROUP BY app_bundle_id, app_name
            ORDER BY total DESC
            LIMIT 1;
            """,
            [.text(start), .text(end)]
        ).first?["app_name"]?.textValue

        let peakHourRow = try query(
            """
            SELECT strftime('%H', minute) AS hour, SUM(total_keys) AS total
            FROM minute_stats
            WHERE minute >= ? AND minute < ?
            GROUP BY hour
            ORDER BY total DESC
            LIMIT 1;
            """,
            [.text(start), .text(end)]
        ).first

        return TodayStats(
            totalKeys: total,
            activeMinutes: row["active_minutes"]?.intValue ?? 0,
            peakHour: peakHourRow?["hour"]?.textValue.flatMap(Int.init),
            topAppName: topApp,
            keyDistribution: distribution
        )
    }

    public func topKeys(period: Period, appBundleID: String? = nil, category: KeyCategory? = nil, limit: Int = 10) throws -> [KeyUsage] {
        var clauses: [String] = ["date >= ?", "date <= ?"]
        var values: [SQLiteValue] = [.text(period.startDay), .text(period.endDay)]

        if let appBundleID {
            clauses.append("app_bundle_id = ?")
            values.append(.text(appBundleID))
        }

        if let category {
            clauses.append("key_category = ?")
            values.append(.text(category.rawValue))
        }

        values.append(.int(limit))
        let rows = try query(
            """
            SELECT key_code, key_name, key_category, app_bundle_id, app_name, SUM(count) AS total
            FROM key_usage_stats
            WHERE \(clauses.joined(separator: " AND "))
            GROUP BY key_code, key_name, key_category, app_bundle_id, app_name
            ORDER BY total DESC
            LIMIT ?;
            """,
            values
        )

        return rows.map { row in
            KeyUsage(
                keyCode: row["key_code"]?.intValue ?? 0,
                keyName: row["key_name"]?.textValue ?? "Unknown",
                category: KeyCategory(rawValue: row["key_category"]?.textValue ?? "") ?? .other,
                appBundleID: row["app_bundle_id"]?.textValue ?? "unknown",
                appName: row["app_name"]?.textValue ?? "Unknown",
                count: row["total"]?.intValue ?? 0
            )
        }
    }

    public static let schema = """
    CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at DATETIME NOT NULL
    );

    CREATE TABLE IF NOT EXISTS minute_stats (
        id INTEGER PRIMARY KEY,
        minute DATETIME NOT NULL,
        app_bundle_id TEXT NOT NULL DEFAULT 'unknown',
        app_name TEXT NOT NULL DEFAULT 'Unknown',
        total_keys INTEGER DEFAULT 0,
        letters INTEGER DEFAULT 0,
        numbers INTEGER DEFAULT 0,
        symbols INTEGER DEFAULT 0,
        function_keys INTEGER DEFAULT 0,
        modifier_keys INTEGER DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_minute_stats_minute ON minute_stats(minute);
    CREATE INDEX IF NOT EXISTS idx_minute_stats_app ON minute_stats(app_bundle_id, minute);
    CREATE UNIQUE INDEX IF NOT EXISTS idx_minute_stats_bucket ON minute_stats(minute, app_bundle_id);

    CREATE TABLE IF NOT EXISTS key_usage_stats (
        id INTEGER PRIMARY KEY,
        date TEXT NOT NULL,
        hour INTEGER NOT NULL,
        app_bundle_id TEXT NOT NULL DEFAULT 'unknown',
        app_name TEXT NOT NULL DEFAULT 'Unknown',
        key_code INTEGER NOT NULL,
        key_name TEXT NOT NULL,
        key_category TEXT NOT NULL,
        count INTEGER DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_key_usage_date ON key_usage_stats(date);
    CREATE INDEX IF NOT EXISTS idx_key_usage_key ON key_usage_stats(key_code, date);
    CREATE INDEX IF NOT EXISTS idx_key_usage_app ON key_usage_stats(app_bundle_id, date);
    CREATE UNIQUE INDEX IF NOT EXISTS idx_key_usage_bucket ON key_usage_stats(date, hour, app_bundle_id, key_code);

    CREATE TABLE IF NOT EXISTS key_events (
        id INTEGER PRIMARY KEY,
        timestamp DATETIME NOT NULL,
        key_code INTEGER NOT NULL,
        key_name TEXT NOT NULL,
        key_category TEXT NOT NULL,
        app_bundle_id TEXT NOT NULL DEFAULT 'unknown',
        app_name TEXT NOT NULL DEFAULT 'Unknown',
        modifiers INTEGER DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_key_events_timestamp ON key_events(timestamp);
    CREATE INDEX IF NOT EXISTS idx_key_events_app ON key_events(app_bundle_id, timestamp);

    CREATE TABLE IF NOT EXISTS daily_stats (
        date TEXT PRIMARY KEY,
        total_keys INTEGER,
        letters INTEGER,
        numbers INTEGER,
        symbols INTEGER,
        function_keys INTEGER,
        top_apps TEXT,
        peak_hour INTEGER,
        active_minutes INTEGER
    );
    """

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .int(let int):
                sqlite3_bind_int64(statement, index, sqlite3_int64(int))
            case .text(let string):
                sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
            case .null:
                sqlite3_bind_null(statement, index)
            }
        }
    }
}

public enum SQLiteValue: Equatable {
    case int(Int)
    case text(String)
    case null

    init(statement: OpaquePointer?, index: Int32) {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            self = .int(Int(sqlite3_column_int64(statement, index)))
        case SQLITE_TEXT:
            self = .text(String(cString: sqlite3_column_text(statement, index)))
        default:
            self = .null
        }
    }

    public var intValue: Int? {
        if case .int(let value) = self { return value }
        if case .text(let value) = self { return Int(value) }
        return nil
    }

    public var textValue: String? {
        if case .text(let value) = self { return value }
        if case .int(let value) = self { return String(value) }
        return nil
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
