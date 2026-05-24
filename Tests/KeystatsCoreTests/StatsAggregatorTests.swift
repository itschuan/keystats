import KeystatsCore
import XCTest

final class StatsAggregatorTests: XCTestCase {
    func testAggregateModeRecordsMinuteAndKeyUsageOnly() {
        let aggregator = StatsAggregator(mode: .aggregate)

        aggregator.record(makeEvent())
        let snapshot = aggregator.snapshot()

        XCTAssertEqual(snapshot.minuteBuckets.count, 1)
        XCTAssertEqual(snapshot.minuteBuckets[0].totalKeys, 1)
        XCTAssertEqual(snapshot.minuteBuckets[0].letters, 1)
        XCTAssertEqual(snapshot.keyUsageBuckets.count, 1)
        XCTAssertEqual(snapshot.keyUsageBuckets[0].count, 1)
        XCTAssertTrue(snapshot.detailEvents.isEmpty)
    }

    func testDetailModeRecordsDetailEvents() {
        let aggregator = StatsAggregator(mode: .detail)

        aggregator.record(makeEvent())

        XCTAssertEqual(aggregator.snapshot().detailEvents.count, 1)
    }

    func testDrainClearsBuckets() {
        let aggregator = StatsAggregator(mode: .detail)
        aggregator.record(makeEvent())

        let drained = aggregator.drain()

        XCTAssertEqual(drained.minuteBuckets.count, 1)
        XCTAssertTrue(aggregator.snapshot().minuteBuckets.isEmpty)
        XCTAssertTrue(aggregator.snapshot().keyUsageBuckets.isEmpty)
        XCTAssertTrue(aggregator.snapshot().detailEvents.isEmpty)
    }

    func testBucketsSplitByAppAndHour() {
        let aggregator = StatsAggregator()
        aggregator.record(makeEvent(app: AppContext(bundleID: "a", name: "A")))
        aggregator.record(makeEvent(date: fixedDate("2026-05-25T11:00:00.000Z"), app: AppContext(bundleID: "b", name: "B")))

        let snapshot = aggregator.snapshot()

        XCTAssertEqual(snapshot.minuteBuckets.count, 2)
        XCTAssertEqual(snapshot.keyUsageBuckets.count, 2)
    }
}

