import Foundation

public struct RetentionManager {
    private let dataStore: SQLiteDataStore

    public init(dataStore: SQLiteDataStore) {
        self.dataStore = dataStore
    }

    public func cleanupDetailEvents(now: Date = Date(), retentionDays: Int = 7) throws {
        let cutoff = DateUtils.calendar.date(byAdding: .day, value: -retentionDays, to: now) ?? now
        try dataStore.deleteDetailEvents(olderThan: cutoff)
    }
}

