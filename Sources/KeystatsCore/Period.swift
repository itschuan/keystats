import Foundation

public struct Period: Equatable {
    public let startDay: String
    public let endDay: String

    public init(startDay: String, endDay: String) {
        self.startDay = startDay
        self.endDay = endDay
    }

    public static func today(_ date: Date = Date()) -> Period {
        let day = DateUtils.dayString(date)
        return Period(startDay: day, endDay: day)
    }

    public static func lastDays(_ days: Int, endingAt date: Date = Date()) -> Period {
        let end = DateUtils.dayString(date)
        let startDate = DateUtils.calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: date) ?? date
        return Period(startDay: DateUtils.dayString(startDate), endDay: end)
    }

    public static func parse(_ raw: String, now: Date = Date()) -> Period {
        if raw == "today" {
            return .today(now)
        }
        if raw.hasSuffix("d"), let days = Int(raw.dropLast()) {
            return .lastDays(days, endingAt: now)
        }
        return .today(now)
    }
}

