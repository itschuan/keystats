import Foundation

public struct MinuteBucket: Equatable {
    public let minute: Date
    public let app: AppContext
    public var totalKeys: Int
    public var letters: Int
    public var numbers: Int
    public var symbols: Int
    public var functionKeys: Int
    public var modifierKeys: Int

    public init(minute: Date, app: AppContext) {
        self.minute = minute
        self.app = app
        self.totalKeys = 0
        self.letters = 0
        self.numbers = 0
        self.symbols = 0
        self.functionKeys = 0
        self.modifierKeys = 0
    }
}

public struct KeyUsageBucket: Equatable {
    public let date: String
    public let hour: Int
    public let app: AppContext
    public let key: KeyDescriptor
    public var count: Int

    public init(date: String, hour: Int, app: AppContext, key: KeyDescriptor, count: Int = 0) {
        self.date = date
        self.hour = hour
        self.app = app
        self.key = key
        self.count = count
    }
}

public final class StatsAggregator {
    private var minuteBuckets: [MinuteBucketKey: MinuteBucket] = [:]
    private var keyUsageBuckets: [KeyUsageBucketKey: KeyUsageBucket] = [:]
    private var detailEvents: [CapturedKeyEvent] = []
    private var mode: StatsMode

    public init(mode: StatsMode = .aggregate) {
        self.mode = mode
    }

    public func setMode(_ mode: StatsMode) {
        self.mode = mode
    }

    public func record(_ event: CapturedKeyEvent) {
        let minute = DateUtils.minuteBucket(event.timestamp)
        let minuteKey = MinuteBucketKey(minute: DateUtils.isoString(minute), appBundleID: event.app.bundleID)
        var minuteBucket = minuteBuckets[minuteKey] ?? MinuteBucket(minute: minute, app: event.app)
        minuteBucket.totalKeys += 1

        switch event.key.category {
        case .letter: minuteBucket.letters += 1
        case .number: minuteBucket.numbers += 1
        case .symbol: minuteBucket.symbols += 1
        case .function, .other: minuteBucket.functionKeys += 1
        case .modifier: minuteBucket.modifierKeys += 1
        }
        minuteBuckets[minuteKey] = minuteBucket

        let keyUsageKey = KeyUsageBucketKey(
            date: DateUtils.dayString(event.timestamp),
            hour: DateUtils.hour(event.timestamp),
            appBundleID: event.app.bundleID,
            keyCode: event.key.keyCode
        )
        var keyUsageBucket = keyUsageBuckets[keyUsageKey] ?? KeyUsageBucket(
            date: keyUsageKey.date,
            hour: keyUsageKey.hour,
            app: event.app,
            key: event.key
        )
        keyUsageBucket.count += 1
        keyUsageBuckets[keyUsageKey] = keyUsageBucket

        if mode == .detail {
            detailEvents.append(event)
        }
    }

    public func snapshot() -> AggregatorSnapshot {
        AggregatorSnapshot(
            minuteBuckets: Array(minuteBuckets.values),
            keyUsageBuckets: Array(keyUsageBuckets.values),
            detailEvents: detailEvents
        )
    }

    public func drain() -> AggregatorSnapshot {
        let result = snapshot()
        minuteBuckets.removeAll()
        keyUsageBuckets.removeAll()
        detailEvents.removeAll()
        return result
    }
}

public struct AggregatorSnapshot: Equatable {
    public let minuteBuckets: [MinuteBucket]
    public let keyUsageBuckets: [KeyUsageBucket]
    public let detailEvents: [CapturedKeyEvent]
}

private struct MinuteBucketKey: Hashable {
    let minute: String
    let appBundleID: String
}

private struct KeyUsageBucketKey: Hashable {
    let date: String
    let hour: Int
    let appBundleID: String
    let keyCode: Int
}

