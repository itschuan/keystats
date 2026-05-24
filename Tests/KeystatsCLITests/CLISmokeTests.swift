import KeystatsCore
import XCTest

final class CLISmokeTests: XCTestCase {
    func testPeriodParsing() {
        let period = Period.parse("7d", now: ISO8601DateFormatter.keystatsCLITestFormatter.date(from: "2026-05-25T00:00:00.000Z")!)

        XCTAssertEqual(period.startDay, "2026-05-19")
        XCTAssertEqual(period.endDay, "2026-05-25")
    }

    func testAnalyzerCanReadEmptyStore() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keystats-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try SQLiteDataStore(path: directory.appendingPathComponent("keystats.db").path)
        defer { store.close() }

        let stats = try Analyzer(dataStore: store).today()

        XCTAssertEqual(stats.totalKeys, 0)
    }
}

extension ISO8601DateFormatter {
    static let keystatsCLITestFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

