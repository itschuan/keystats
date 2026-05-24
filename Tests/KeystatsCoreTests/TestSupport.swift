import Foundation
import KeystatsCore
import XCTest

func makeTemporaryStore(file: StaticString = #filePath, line: UInt = #line) throws -> SQLiteDataStore {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("keystats-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try SQLiteDataStore(path: directory.appendingPathComponent("keystats.db").path)
}

func fixedDate(_ iso: String = "2026-05-25T10:15:30.000Z") -> Date {
    ISO8601DateFormatter.keystatsTestFormatter.date(from: iso)!
}

extension ISO8601DateFormatter {
    static let keystatsTestFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

let testApp = AppContext(bundleID: "com.example.Editor", name: "Editor")

func makeEvent(
    keyCode: Int = 0,
    keyName: String = "A",
    category: KeyCategory = .letter,
    date: Date = fixedDate(),
    app: AppContext = testApp
) -> CapturedKeyEvent {
    CapturedKeyEvent(
        timestamp: date,
        key: KeyDescriptor(keyCode: keyCode, keyName: keyName, category: category),
        app: app
    )
}

