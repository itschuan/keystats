import AppKit
import Foundation
import KeystatsCore
import SwiftUI

@main
struct KeystatsLiteApp: App {
    @StateObject private var model = LiteModel()

    var body: some Scene {
        MenuBarExtra {
            LitePanel(model: model)
                .frame(width: 340)
                .onAppear {
                    model.refresh()
                }
        } label: {
            MenuBarCounterLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarCounterLabel: View {
    @ObservedObject var model: LiteModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "keyboard")
            Text(model.menuTitle)
                .monospacedDigit()
        }
    }
}

@MainActor
final class LiteModel: ObservableObject {
    @Published var permissionGranted = false
    @Published var mode: StatsMode = .aggregate
    @Published var today = TodayStats(totalKeys: 0, activeMinutes: 0, peakHour: nil, topAppName: nil, keyDistribution: [:])
    @Published var topApps: [AppUsage] = []
    @Published var topKeys: [KeyUsage] = []
    @Published var dailyUsage: [DailyUsage] = []
    @Published var lastError: String?
    @Published var statusMessage: String?
    @Published private var pendingKeyCount = 0

    private let environment = LiteEnvironment.default
    private lazy var logger = LiteLogger(logURL: environment.logURL)
    private let permissionChecker = PermissionChecker()
    private let supervisor = EventTapSupervisor()
    private let aggregator = StatsAggregator()
    private var store: SQLiteDataStore?
    private var refreshTimer: Timer?
    private var flushTimer: Timer?

    var menuTitle: String {
        permissionGranted ? compact(liveTotalKeys) : "Setup"
    }

    var liveTotalKeys: Int {
        today.totalKeys + pendingKeyCount
    }

    init() {
        configure()
    }

    func configure() {
        do {
            try environment.prepare()
            logger.log("configure appVersion=0.1.0 database=\(environment.databaseURL.path)")
            store = try SQLiteDataStore(path: environment.databaseURL.path)
            mode = LiteConfig.load(from: environment.configURL).mode
            aggregator.setMode(mode)
            logger.log("store opened mode=\(mode.rawValue)")
            refresh()
            startTimers()
            startListeningIfAllowed()
        } catch {
            lastError = "\(error)"
            logger.log("configure failed error=\(error)")
        }
    }

    func requestPermission() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        logger.log("request input monitoring access")
        _ = permissionChecker.requestInputMonitoringAccess()
        startListeningIfAllowed()
        refresh()
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func retryPermissionCheck() {
        logger.log("retry permission check preflight=\(permissionChecker.status().inputMonitoringGranted)")
        startListeningIfAllowed()
        refresh()
    }

    func refresh() {
        permissionGranted = permissionChecker.status().inputMonitoringGranted || supervisor.status == .running
        do {
            today = try store?.todayStats() ?? today
            topApps = try store?.topApps(limit: 3) ?? []
            topKeys = try store?.topKeys(period: .today(), limit: 10) ?? []
            dailyUsage = try store?.dailyUsage(days: 7) ?? []
            mode = LiteConfig.load(from: environment.configURL).mode
            aggregator.setMode(mode)
        } catch {
            lastError = "\(error)"
            logger.log("refresh failed error=\(error)")
        }
    }

    func setMode(_ newMode: StatsMode) {
        mode = newMode
        aggregator.setMode(newMode)
        do {
            try LiteConfig(mode: newMode).save(to: environment.configURL)
            logger.log("mode changed mode=\(newMode.rawValue)")
        } catch {
            lastError = "\(error)"
            logger.log("mode save failed error=\(error)")
        }
    }

    func clearData() {
        do {
            logger.log("clear data requested liveTotal=\(liveTotalKeys) pending=\(pendingKeyCount)")
            _ = aggregator.drain()
            pendingKeyCount = 0
            try store?.clearAllData()
            refresh()
            logger.log("clear data completed today=\(today.totalKeys)")
            statusMessage = "Data cleared."
        } catch {
            lastError = "\(error)"
            logger.log("clear data failed error=\(error)")
        }
    }

    func quit() {
        logger.log("quit requested liveTotal=\(liveTotalKeys) pending=\(pendingKeyCount)")
        flush()
        NSApplication.shared.terminate(nil)
    }

    func revealLog() {
        logger.log("reveal log requested")
        NSWorkspace.shared.activateFileViewerSelecting([environment.logURL])
    }

    private func startListeningIfAllowed() {
        let status = supervisor.start { [weak self] event in
            Task { @MainActor in
                self?.record(event)
            }
        }
        permissionGranted = status == .running
        logger.log("listener start status=\(status.rawValue) preflight=\(permissionChecker.status().inputMonitoringGranted)")
        if status == .error {
            lastError = "Keyboard listener could not start."
        }
    }

    private func startTimers() {
        refreshTimer?.invalidate()
        flushTimer?.invalidate()
        logger.log("start timers refresh=2s flush=5s")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.startListeningIfAllowed()
            }
        }
        flushTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flush()
            }
        }
    }

    private func flush() {
        let snapshot = aggregator.drain()
        do {
            let eventCount = snapshot.minuteBuckets.reduce(0) { $0 + $1.totalKeys }
            try store?.upsertMinuteStats(snapshot.minuteBuckets)
            try store?.upsertKeyUsage(snapshot.keyUsageBuckets)
            try store?.insertKeyEvents(snapshot.detailEvents)
            pendingKeyCount = 0
            today = try store?.todayStats() ?? today
            topApps = try store?.topApps(limit: 3) ?? []
            topKeys = try store?.topKeys(period: .today(), limit: 10) ?? []
            dailyUsage = try store?.dailyUsage(days: 7) ?? []
            if eventCount > 0 {
                logger.log("flush events=\(eventCount) minuteBuckets=\(snapshot.minuteBuckets.count) keyBuckets=\(snapshot.keyUsageBuckets.count) detailEvents=\(snapshot.detailEvents.count) today=\(today.totalKeys)")
            }
        } catch {
            lastError = "\(error)"
            logger.log("flush failed error=\(error)")
        }
    }

    private func record(_ event: CapturedKeyEvent) {
        aggregator.record(event)
        pendingKeyCount += 1
        statusMessage = nil
        if pendingKeyCount == 1 || pendingKeyCount.isMultiple(of: 100) {
            logger.log("record pending=\(pendingKeyCount) liveTotal=\(liveTotalKeys)")
        }
    }

    private func compact(_ value: Int) -> String {
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000.0)
        }
        return "\(value)"
    }
}

struct LitePanel: View {
    @ObservedObject var model: LiteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.permissionGranted {
                TodaySection(model: model)
                TrendSection(days: model.dailyUsage)
                TopAppsSection(apps: model.topApps)
                TopKeysSection(keys: model.topKeys)
                SettingsSection(model: model)
            } else {
                PermissionGuide(model: model)
            }

            if let message = model.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(16)
    }
}

struct TodaySection: View {
    @ObservedObject var model: LiteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.headline)
            Text("\(model.liveTotalKeys) keys")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            HStack(spacing: 14) {
                StatPill(title: "Active", value: "\(model.today.activeMinutes)m")
                if let peakHour = model.today.peakHour {
                    StatPill(title: "Peak", value: String(format: "%02d:00", peakHour))
                }
            }
        }
    }
}

struct TrendSection: View {
    let days: [DailyUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 Days")
                .font(.headline)
            let maxValue = max(days.map(\.totalKeys).max() ?? 1, 1)
            ForEach(days, id: \.date) { day in
                HStack(spacing: 8) {
                    Text(label(for: day.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.blue)
                            .frame(width: max(4, proxy.size.width * CGFloat(day.totalKeys) / CGFloat(maxValue)))
                    }
                    .frame(height: 8)
                    Text("\(day.totalKeys)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
            }
        }
    }

    private func label(for date: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let parsed = formatter.date(from: date) else { return date }
        formatter.dateFormat = "EEE"
        return formatter.string(from: parsed)
    }
}

struct TopAppsSection: View {
    let apps: [AppUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Apps")
                .font(.headline)
            if apps.isEmpty {
                Text("No app data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(apps, id: \.bundleID) { app in
                    HStack {
                        Text(app.name)
                            .lineLimit(1)
                        Spacer()
                        Text("\(app.totalKeys)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct TopKeysSection: View {
    let keys: [KeyUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top 10 Keys")
                .font(.headline)
            if keys.isEmpty {
                Text("No key data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Text(key.keyName)
                            .lineLimit(1)
                        Spacer()
                        Text("\(key.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct SettingsSection: View {
    @ObservedObject var model: LiteModel

    var body: some View {
        Divider()
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: Binding(
                get: { model.mode },
                set: { model.setMode($0) }
            )) {
                Text("Aggregate").tag(StatsMode.aggregate)
                Text("Detail").tag(StatsMode.detail)
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Clear Data", role: .destructive) {
                    model.clearData()
                }
                Button("Reveal Log") {
                    model.revealLog()
                }
                Spacer()
                Button("Quit") {
                    model.quit()
                }
            }
        }
    }
}

struct PermissionGuide: View {
    @ObservedObject var model: LiteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "keyboard.badge.eye")
                .font(.system(size: 30))
                .foregroundStyle(.blue)
            Text("Input Monitoring Required")
                .font(.headline)
            Text("Keystats needs Input Monitoring permission to count keyboard usage. It stores statistics locally on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Request Access") {
                    model.requestPermission()
                }
                Button("Open Settings") {
                    model.openInputMonitoringSettings()
                }
                Button("Refresh") {
                    model.retryPermissionCheck()
                }
            }
            Text("If Keystats is already enabled, click Refresh. If it still stays here, quit Keystats and open it again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }
}

struct LiteEnvironment {
    let homeDirectory: URL

    static var `default`: LiteEnvironment {
        LiteEnvironment(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    var keystatsDirectory: URL {
        homeDirectory.appendingPathComponent(".keystats", isDirectory: true)
    }

    var databaseURL: URL {
        keystatsDirectory.appendingPathComponent("keystats.db")
    }

    var configURL: URL {
        keystatsDirectory.appendingPathComponent("lite.config.json")
    }

    var logURL: URL {
        keystatsDirectory.appendingPathComponent("keystats-lite.log")
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: keystatsDirectory, withIntermediateDirectories: true)
    }
}

final class LiteLogger {
    private let logURL: URL
    private let queue = DispatchQueue(label: "dev.keystats.lite.logger")
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(logURL: URL) {
        self.logURL = logURL
    }

    func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async { [logURL] in
            do {
                let parent = logURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                rotateIfNeeded(logURL)
                if FileManager.default.fileExists(atPath: logURL.path) {
                    let handle = try FileHandle(forWritingTo: logURL)
                    try handle.seekToEnd()
                    if let data = line.data(using: .utf8) {
                        try handle.write(contentsOf: data)
                    }
                    try handle.close()
                } else {
                    try line.write(to: logURL, atomically: true, encoding: .utf8)
                }
            } catch {
                NSLog("Keystats Lite log failed: \(error)")
            }
        }
    }
}

private func rotateIfNeeded(_ logURL: URL) {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
          let size = attributes[.size] as? NSNumber,
          size.intValue > 1_000_000 else {
        return
    }

    let rotated = logURL.deletingPathExtension().appendingPathExtension("old.log")
    try? FileManager.default.removeItem(at: rotated)
    try? FileManager.default.moveItem(at: logURL, to: rotated)
}

struct LiteConfig: Codable {
    var mode: StatsMode = .aggregate

    static func load(from url: URL) -> LiteConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(LiteConfig.self, from: data) else {
            return LiteConfig()
        }
        return config
    }

    func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
