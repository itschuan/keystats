import KeystatsCore
import XCTest

final class SQLiteDataStoreTests: XCTestCase {
    func testCreatesSchemaAndMigrationRecord() throws {
        let store = try makeTemporaryStore()
        defer { store.close() }

        let rows = try store.query("SELECT version FROM schema_migrations;")

        XCTAssertEqual(rows.first?["version"]?.intValue, 1)
    }

    func testMinuteStatsUpsertAggregatesWithoutDuplicates() throws {
        let store = try makeTemporaryStore()
        defer { store.close() }
        let aggregator = StatsAggregator()
        aggregator.record(makeEvent())
        aggregator.record(makeEvent())
        let snapshot = aggregator.drain()

        try store.upsertMinuteStats(snapshot.minuteBuckets)
        try store.upsertMinuteStats(snapshot.minuteBuckets)

        let rows = try store.query("SELECT COUNT(*) AS rows_count, SUM(total_keys) AS total FROM minute_stats;")
        XCTAssertEqual(rows.first?["rows_count"]?.intValue, 1)
        XCTAssertEqual(rows.first?["total"]?.intValue, 4)
    }

    func testKeyUsageUpsertAggregatesWithoutDuplicates() throws {
        let store = try makeTemporaryStore()
        defer { store.close() }
        let aggregator = StatsAggregator()
        aggregator.record(makeEvent(keyCode: 36, keyName: "Return", category: .function))
        aggregator.record(makeEvent(keyCode: 36, keyName: "Return", category: .function))
        let snapshot = aggregator.drain()

        try store.upsertKeyUsage(snapshot.keyUsageBuckets)
        try store.upsertKeyUsage(snapshot.keyUsageBuckets)

        let rows = try store.query("SELECT COUNT(*) AS rows_count, SUM(count) AS total FROM key_usage_stats;")
        XCTAssertEqual(rows.first?["rows_count"]?.intValue, 1)
        XCTAssertEqual(rows.first?["total"]?.intValue, 4)
    }

    func testUnknownAppIsNotNullable() throws {
        let store = try makeTemporaryStore()
        defer { store.close() }
        let event = makeEvent(app: AppContext(bundleID: nil, name: nil))
        let aggregator = StatsAggregator()
        aggregator.record(event)
        let snapshot = aggregator.drain()

        try store.upsertMinuteStats(snapshot.minuteBuckets)
        try store.upsertKeyUsage(snapshot.keyUsageBuckets)

        let minute = try store.query("SELECT app_bundle_id, app_name FROM minute_stats;").first
        let usage = try store.query("SELECT app_bundle_id, app_name FROM key_usage_stats;").first
        XCTAssertEqual(minute?["app_bundle_id"]?.textValue, "unknown")
        XCTAssertEqual(minute?["app_name"]?.textValue, "Unknown")
        XCTAssertEqual(usage?["app_bundle_id"]?.textValue, "unknown")
        XCTAssertEqual(usage?["app_name"]?.textValue, "Unknown")
    }

    func testTodayStatsAndTopKeys() throws {
        let store = try makeTemporaryStore()
        defer { store.close() }
        let aggregator = StatsAggregator()
        aggregator.record(makeEvent(keyCode: 0, keyName: "A", category: .letter))
        aggregator.record(makeEvent(keyCode: 36, keyName: "Return", category: .function))
        let snapshot = aggregator.drain()
        try store.upsertMinuteStats(snapshot.minuteBuckets)
        try store.upsertKeyUsage(snapshot.keyUsageBuckets)

        let stats = try store.todayStats(on: fixedDate())
        let keys = try store.topKeys(period: .today(fixedDate()), limit: 10)

        XCTAssertEqual(stats.totalKeys, 2)
        XCTAssertEqual(stats.keyDistribution[.letter], 1)
        XCTAssertEqual(stats.keyDistribution[.function], 1)
        XCTAssertEqual(stats.topAppName, "Editor")
        XCTAssertEqual(keys.count, 2)
    }

    func testTopAppsReturnsAppsForToday() throws {
        let store = try makeTemporaryStore()
        defer { store.close() }
        let aggregator = StatsAggregator()
        let browser = AppContext(bundleID: "com.example.Browser", name: "Browser")

        aggregator.record(makeEvent(app: browser))
        aggregator.record(makeEvent(app: browser))
        aggregator.record(makeEvent(app: testApp))
        let snapshot = aggregator.drain()
        try store.upsertMinuteStats(snapshot.minuteBuckets)

        let apps = try store.topApps(on: fixedDate(), limit: 2)

        XCTAssertEqual(apps.map(\.name), ["Browser", "Editor"])
        XCTAssertEqual(apps.map(\.totalKeys), [2, 1])
    }

    func testDailyUsageFillsMissingDays() throws {
        let store = try makeTemporaryStore()
        defer { store.close() }
        let aggregator = StatsAggregator()

        aggregator.record(makeEvent(date: fixedDate("2026-05-24T10:00:00.000Z")))
        aggregator.record(makeEvent(date: fixedDate("2026-05-25T10:00:00.000Z")))
        aggregator.record(makeEvent(date: fixedDate("2026-05-25T11:00:00.000Z")))
        let snapshot = aggregator.drain()
        try store.upsertMinuteStats(snapshot.minuteBuckets)

        let days = try store.dailyUsage(days: 3, endingOn: fixedDate())

        XCTAssertEqual(days.map(\.date), ["2026-05-23", "2026-05-24", "2026-05-25"])
        XCTAssertEqual(days.map(\.totalKeys), [0, 1, 2])
    }

    func testRetentionDeletesOldDetailEvents() throws {
        let store = try makeTemporaryStore()
        defer { store.close() }
        try store.insertKeyEvents([
            makeEvent(date: fixedDate("2026-05-01T00:00:00.000Z")),
            makeEvent(date: fixedDate("2026-05-24T00:00:00.000Z"))
        ])

        try RetentionManager(dataStore: store).cleanupDetailEvents(now: fixedDate("2026-05-25T00:00:00.000Z"), retentionDays: 7)

        let rows = try store.query("SELECT COUNT(*) AS total FROM key_events;")
        XCTAssertEqual(rows.first?["total"]?.intValue, 1)
    }
}
