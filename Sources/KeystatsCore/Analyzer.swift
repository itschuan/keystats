import Foundation

public struct Analyzer {
    private let dataStore: SQLiteDataStore

    public init(dataStore: SQLiteDataStore) {
        self.dataStore = dataStore
    }

    public func today(date: Date = Date()) throws -> TodayStats {
        try dataStore.todayStats(on: date)
    }

    public func topKeys(period: Period, appBundleID: String? = nil, category: KeyCategory? = nil, limit: Int = 10) throws -> [KeyUsage] {
        try dataStore.topKeys(period: period, appBundleID: appBundleID, category: category, limit: limit)
    }
}

