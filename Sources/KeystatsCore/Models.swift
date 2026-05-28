import Foundation

public enum KeyCategory: String, Codable, CaseIterable, Equatable {
    case letter
    case number
    case symbol
    case function
    case modifier
    case other
}

public enum StatsMode: String, Codable, Equatable {
    case aggregate
    case detail
}

public enum ListenerStatus: String, Codable, Equatable {
    case stopped
    case running
    case paused
    case permissionRequired = "permission_required"
    case error
}

public struct AppContext: Codable, Equatable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String?, name: String?) {
        self.bundleID = (bundleID?.isEmpty == false) ? bundleID! : "unknown"
        self.name = (name?.isEmpty == false) ? name! : "Unknown"
    }

    public static let unknown = AppContext(bundleID: "unknown", name: "Unknown")
}

public struct KeyDescriptor: Codable, Equatable {
    public let keyCode: Int
    public let keyName: String
    public let category: KeyCategory
    public let modifiers: Int

    public init(keyCode: Int, keyName: String, category: KeyCategory, modifiers: Int = 0) {
        self.keyCode = keyCode
        self.keyName = keyName
        self.category = category
        self.modifiers = modifiers
    }
}

public struct CapturedKeyEvent: Codable, Equatable {
    public let timestamp: Date
    public let key: KeyDescriptor
    public let app: AppContext

    public init(timestamp: Date, key: KeyDescriptor, app: AppContext) {
        self.timestamp = timestamp
        self.key = key
        self.app = app
    }
}

public struct TodayStats: Codable, Equatable {
    public let totalKeys: Int
    public let activeMinutes: Int
    public let peakHour: Int?
    public let topAppName: String?
    public let keyDistribution: [KeyCategory: Int]

    public init(
        totalKeys: Int,
        activeMinutes: Int,
        peakHour: Int?,
        topAppName: String?,
        keyDistribution: [KeyCategory: Int]
    ) {
        self.totalKeys = totalKeys
        self.activeMinutes = activeMinutes
        self.peakHour = peakHour
        self.topAppName = topAppName
        self.keyDistribution = keyDistribution
    }
}

public struct KeyUsage: Codable, Equatable {
    public let keyCode: Int
    public let keyName: String
    public let category: KeyCategory
    public let appBundleID: String
    public let appName: String
    public let count: Int

    public init(
        keyCode: Int,
        keyName: String,
        category: KeyCategory,
        appBundleID: String,
        appName: String,
        count: Int
    ) {
        self.keyCode = keyCode
        self.keyName = keyName
        self.category = category
        self.appBundleID = appBundleID
        self.appName = appName
        self.count = count
    }
}

public struct AppUsage: Codable, Equatable {
    public let bundleID: String
    public let name: String
    public let totalKeys: Int

    public init(bundleID: String, name: String, totalKeys: Int) {
        self.bundleID = bundleID
        self.name = name
        self.totalKeys = totalKeys
    }
}

public struct DailyUsage: Codable, Equatable {
    public let date: String
    public let totalKeys: Int

    public init(date: String, totalKeys: Int) {
        self.date = date
        self.totalKeys = totalKeys
    }
}
