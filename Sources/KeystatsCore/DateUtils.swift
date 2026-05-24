import Foundation

enum DateUtils {
    static let calendar = Calendar(identifier: .gregorian)

    static func minuteBucket(_ date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: comps) ?? date
    }

    static func dayString(_ date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let year = comps.year ?? 1970
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func hour(_ date: Date) -> Int {
        calendar.component(.hour, from: date)
    }

    static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter.keystatsFormatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        ISO8601DateFormatter.keystatsFormatter.date(from: string)
    }
}

extension ISO8601DateFormatter {
    static let keystatsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

