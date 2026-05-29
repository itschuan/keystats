import AppKit
import Darwin
import Foundation
import KeystatsCore
import SwiftUI

private enum LiteAppInfo {
    static let version = "0.1.0"

    static var displayVersion: String {
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        guard let bundleVersion, !bundleVersion.isEmpty else {
            return "\(version) (dev)"
        }
        return "\(version) (\(bundleVersion))"
    }
}

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
    @Published var inputMonitoringGranted = false
    @Published var accessibilityGranted = false
    @Published var mode: StatsMode = .aggregate
    @Published var today = TodayStats(totalKeys: 0, activeMinutes: 0, peakHour: nil, topAppName: nil, keyDistribution: [:])
    @Published var topApps: [AppUsage] = []
    @Published var topKeys: [KeyUsage] = []
    @Published var dailyUsage: [DailyUsage] = []
    @Published var lastError: String?
    @Published var statusMessage: String?
    @Published var listenerStatus: String = "stopped"
    @Published var lastEventAt: Date?
    @Published var lastFlushAt: Date?
    @Published var lastFlushEvents = 0
    @Published var lastRestartAt: Date?
    @Published var restartCount = 0
    @Published var eventTapDiagnostics = EventTapDiagnostics.empty
    @Published var secureInputStatus = SecureInputStatus.unavailable
    @Published private var pendingKeyCount = 0

    private let environment = LiteEnvironment.default
    private lazy var logger = LiteLogger(logURL: environment.logURL)
    private let permissionChecker = PermissionChecker()
    private let supervisor = EventTapSupervisor()
    private let aggregator = StatsAggregator()
    private var instanceLock: SingleInstanceLock?
    private var store: SQLiteDataStore?
    private var refreshTimer: Timer?
    private var flushTimer: Timer?
    private var lastLoggedSecureInputDescription = ""
    private var recordSequence = 0
    private var flushSequence = 0
    private var lastLoggedTodayTotal: Int?
    private var lastProcessSweepAt: Date?

    var menuTitle: String {
        inputMonitoringGranted || accessibilityGranted ? compact(liveTotalKeys) : "Setup"
    }

    var liveTotalKeys: Int {
        today.totalKeys + pendingKeyCount
    }

    var databasePath: String {
        environment.databaseURL.path
    }

    var logPath: String {
        environment.logURL.path
    }

    var processDescription: String {
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        return "pid=\(pid) bundle=\(bundleID)"
    }

    var appVersion: String {
        LiteAppInfo.displayVersion
    }

    var canTrackInBackground: Bool {
        inputMonitoringGranted
    }

    var secureInputDescription: String {
        guard secureInputStatus.isAvailable else { return "unknown" }
        guard secureInputStatus.isEnabled else { return "off" }
        guard let pid = secureInputStatus.pid else { return "on" }
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           let name = app.localizedName {
            return "on by \(name) (\(pid))"
        }
        return "on by pid \(pid)"
    }

    var eventTapDescription: String {
        let diagnostics = eventTapDiagnostics
        let last = diagnostics.lastEventType.map { type in
            if let keyCode = diagnostics.lastKeyCode {
                return " last \(type):\(keyCode)"
            }
            return " last \(type)"
        } ?? ""
        return "\(diagnostics.location.rawValue) keys=\(diagnostics.keyDownEvents) flags=\(diagnostics.flagsChangedEvents) disabled=\(diagnostics.tapDisabledEvents)\(last)"
    }

    var todayWindowDescription: String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    init() {
        configure()
    }

    func configure() {
        do {
            try environment.prepare()
            logger.log("startup appVersion=\(LiteAppInfo.displayVersion) \(processDescription) executable=\(Bundle.main.executableURL?.path ?? "unknown") lock=\(environment.lockURL.path)")
            instanceLock = try SingleInstanceLock(url: environment.lockURL, logger: logger)
            terminateOtherRunningInstances()
            logger.log("configure appVersion=\(LiteAppInfo.displayVersion) \(processDescription) executable=\(Bundle.main.executableURL?.path ?? "unknown") database=\(environment.databaseURL.path)")
            store = try SQLiteDataStore(path: environment.databaseURL.path)
            mode = LiteConfig.load(from: environment.configURL).mode
            aggregator.setMode(mode)
            logger.log("store opened mode=\(mode.rawValue)")
            refresh()
            startTimers()
            startListeningIfAllowed()
        } catch {
            lastError = "\(error)"
            listenerStatus = "error"
            logger.log("configure failed error=\(error)")
        }
    }

    private func terminateOtherRunningInstances() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier
        let scannedProcesses = KeystatsProcessScanner.runningKeystatsProcesses()
        logger.log("process scan current=\(currentPID) found=\(scannedProcesses.map { "\($0.pid):\($0.path)" }.joined(separator: ","))")
        let runningAppCandidates = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != currentPID else { return false }
            if let bundleID, app.bundleIdentifier == bundleID {
                return true
            }
            if app.executableURL.map({ KeystatsProcessScanner.isKeystatsPath($0.path) }) == true {
                return true
            }
            if app.localizedName == "Keystats" || app.localizedName == "Keystats Lite" {
                return true
            }
            return false
        }

        var terminatedPIDs = Set<pid_t>()
        for app in runningAppCandidates {
            terminatedPIDs.insert(app.processIdentifier)
            logger.log("terminate duplicate instance pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "unknown") name=\(app.localizedName ?? "unknown") executable=\(app.executableURL?.path ?? "unknown")")
            app.terminate()
        }

        let backgroundCandidates = scannedProcesses
            .filter { $0.pid != currentPID && !terminatedPIDs.contains($0.pid) }
        for process in backgroundCandidates {
            terminatedPIDs.insert(process.pid)
            logger.log("terminate duplicate background process pid=\(process.pid) executable=\(process.path)")
            kill(process.pid, SIGTERM)
        }

        guard !terminatedPIDs.isEmpty else { return }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let livePIDs = KeystatsProcessScanner.runningKeystatsProcesses()
                .map(\.pid)
                .filter { $0 != currentPID && terminatedPIDs.contains($0) }
            if livePIDs.isEmpty { return }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        for pid in terminatedPIDs where KeystatsProcessScanner.isRunning(pid: pid) {
            logger.log("force terminate duplicate process pid=\(pid)")
            kill(pid, SIGKILL)
        }

        for app in runningAppCandidates where !app.isTerminated {
            logger.log("force terminate duplicate instance pid=\(app.processIdentifier)")
            app.forceTerminate()
        }
    }

    func requestPermission() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        logger.log("request input monitoring access")
        _ = permissionChecker.requestInputMonitoringAccess()
        openInputMonitoringSettings()
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
        sweepOtherProcessesIfNeeded()
        let permissions = permissionChecker.status()
        inputMonitoringGranted = permissions.inputMonitoringGranted
        accessibilityGranted = permissions.accessibilityGranted
        permissionGranted = inputMonitoringGranted || supervisor.status == .running
        eventTapDiagnostics = supervisor.diagnostics()
        secureInputStatus = SecureInputChecker.status()
        if secureInputDescription != lastLoggedSecureInputDescription {
            lastLoggedSecureInputDescription = secureInputDescription
            logger.log("secure input status \(secureInputDescription)")
        }
        do {
            let previousToday = today.totalKeys
            let previousPending = pendingKeyCount
            today = try store?.todayStats() ?? today
            topApps = try store?.topApps(limit: 3) ?? []
            topKeys = try store?.topKeys(period: .today(), limit: 10) ?? []
            dailyUsage = try store?.dailyUsage(days: 7) ?? []
            mode = LiteConfig.load(from: environment.configURL).mode
            aggregator.setMode(mode)
            if lastLoggedTodayTotal != today.totalKeys || previousPending > 0 {
                logger.log("refresh todayBefore=\(previousToday) todayAfter=\(today.totalKeys) pending=\(pendingKeyCount) live=\(liveTotalKeys) listener=\(listenerStatus)")
                lastLoggedTodayTotal = today.totalKeys
            }
        } catch {
            lastError = "\(error)"
            logger.log("refresh failed error=\(error)")
        }
    }

    private func sweepOtherProcessesIfNeeded() {
        let now = Date()
        if let lastProcessSweepAt, now.timeIntervalSince(lastProcessSweepAt) < 5 {
            return
        }
        lastProcessSweepAt = now
        terminateOtherRunningInstances()
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
        stopListening()
        NSApplication.shared.terminate(nil)
    }

    func revealLog() {
        logger.log("reveal log requested")
        NSWorkspace.shared.activateFileViewerSelecting([environment.logURL])
    }

    func restartTracking() {
        logger.log("restart tracking requested status=\(listenerStatus) liveTotal=\(liveTotalKeys) pending=\(pendingKeyCount)")
        flush()
        stopListening()
        startListeningIfAllowed(force: true)
        refresh()
        restartCount += 1
        lastRestartAt = Date()
        statusMessage = listenerStatus == "running" ? "Tracking restarted." : "Tracking restart failed: \(listenerStatus)."
        logger.log("restart tracking completed status=\(listenerStatus) preflight=\(permissionChecker.status().inputMonitoringGranted)")
    }

    private func startListeningIfAllowed(force: Bool = false) {
        if supervisor.status == .running && !force {
            listenerStatus = "running"
            permissionGranted = true
            return
        }

        if force {
            stopListening()
        }

        let status = supervisor.start { [weak self] event in
            Task { @MainActor in
                self?.record(event)
            }
        }
        listenerStatus = status.rawValue
        permissionGranted = status == .running
        let permissions = permissionChecker.status()
        inputMonitoringGranted = permissions.inputMonitoringGranted
        accessibilityGranted = permissions.accessibilityGranted
        eventTapDiagnostics = supervisor.diagnostics()
        secureInputStatus = SecureInputChecker.status()
        logger.log("listener eventtap start status=\(status.rawValue) preflight=\(permissionChecker.status().inputMonitoringGranted) tap=\(eventTapDescription) secureInput=\(secureInputDescription)")
        if status == .error {
            lastError = "Keyboard listener could not start."
        }
    }

    private func stopListening() {
        supervisor.stop()
        listenerStatus = "stopped"
        eventTapDiagnostics = supervisor.diagnostics()
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
        flushSequence += 1
        let sequence = flushSequence
        let pendingBefore = pendingKeyCount
        let todayBefore = today.totalKeys
        let liveBefore = liveTotalKeys
        let snapshot = aggregator.drain()
        do {
            let eventCount = snapshot.minuteBuckets.reduce(0) { $0 + $1.totalKeys }
            if eventCount > 0 || pendingBefore > 0 {
                logger.log("flush#\(sequence) begin events=\(eventCount) pendingBefore=\(pendingBefore) todayBefore=\(todayBefore) liveBefore=\(liveBefore) minuteBuckets=\(snapshot.minuteBuckets.count) keyBuckets=\(snapshot.keyUsageBuckets.count)")
            }
            try store?.upsertMinuteStats(snapshot.minuteBuckets)
            try store?.upsertKeyUsage(snapshot.keyUsageBuckets)
            try store?.insertKeyEvents(snapshot.detailEvents)
            pendingKeyCount = 0
            today = try store?.todayStats() ?? today
            topApps = try store?.topApps(limit: 3) ?? []
            topKeys = try store?.topKeys(period: .today(), limit: 10) ?? []
            dailyUsage = try store?.dailyUsage(days: 7) ?? []
            lastFlushAt = Date()
            lastFlushEvents = eventCount
            if eventCount > 0 {
                logger.log("flush#\(sequence) end events=\(eventCount) pendingAfter=\(pendingKeyCount) todayAfter=\(today.totalKeys) liveAfter=\(liveTotalKeys) detailEvents=\(snapshot.detailEvents.count)")
            }
        } catch {
            lastError = "\(error)"
            logger.log("flush#\(sequence) failed events=\(snapshot.minuteBuckets.reduce(0) { $0 + $1.totalKeys }) pendingBefore=\(pendingBefore) error=\(error)")
        }
    }

    private func record(_ event: CapturedKeyEvent) {
        recordSequence += 1
        let sequence = recordSequence
        let pendingBefore = pendingKeyCount
        let todayBefore = today.totalKeys
        aggregator.record(event)
        pendingKeyCount += 1
        lastEventAt = event.timestamp
        statusMessage = nil
        logger.log("record#\(sequence) keyCode=\(event.key.keyCode) key=\(event.key.keyName) category=\(event.key.category.rawValue) app=\(event.app.bundleID) pendingBefore=\(pendingBefore) pendingAfter=\(pendingKeyCount) today=\(todayBefore) liveAfter=\(liveTotalKeys)")
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
        VStack(alignment: .leading, spacing: 12) {
            if model.canTrackInBackground {
                ScrollView {
                    PanelContent(model: model)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
                }
                .frame(height: 520)
                .scrollIndicators(.hidden)
                SettingsSection(model: model)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        PermissionGuide(model: model)
                        if model.permissionGranted {
                            BackgroundPermissionWarning(model: model)
                        }
                        DiagnosticsSection(model: model)
                        StatusMessages(model: model)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
                }
                .frame(height: 320)
                .scrollIndicators(.hidden)
                SettingsSection(model: model)
            }
        }
        .padding(16)
    }
}

struct PanelContent: View {
    @ObservedObject var model: LiteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TodaySection(model: model)
            TrendSection(days: model.dailyUsage)
            TopAppsSection(apps: model.topApps)
            TopKeysSection(keys: model.topKeys)
            DiagnosticsSection(model: model)
            StatusMessages(model: model)
        }
    }
}

struct StatusMessages: View {
    @ObservedObject var model: LiteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
    }
}

struct BackgroundPermissionWarning: View {
    @ObservedObject var model: LiteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Background tracking needs permission", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            HStack {
                if !model.inputMonitoringGranted {
                    Button("Input Monitoring") {
                        model.requestPermission()
                    }
                }
                Button("Refresh") {
                    model.retryPermissionCheck()
                }
            }
            Text("Right now Keystats can only count while this panel is open.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("If it still does not work after allowing Input Monitoring, remove Keystats from Input Monitoring and add it again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                Button("Restart Tracking") {
                    model.restartTracking()
                }
                Spacer()
            }

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

            HStack {
                Spacer()
                Text("Version \(model.appVersion)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DiagnosticsSection: View {
    @ObservedObject var model: LiteModel

    var body: some View {
        DisclosureGroup("Diagnostics") {
            VStack(alignment: .leading, spacing: 6) {
                DiagnosticRow(label: "Input", value: model.inputMonitoringGranted ? "granted" : "missing")
                DiagnosticRow(label: "Listener", value: model.listenerStatus)
                DiagnosticRow(label: "Secure", value: model.secureInputDescription)
                DiagnosticRow(label: "Events", value: model.eventTapDescription)
                DiagnosticRow(label: "Today", value: model.todayWindowDescription)
                DiagnosticRow(label: "Pending", value: "\(model.liveTotalKeys - model.today.totalKeys)")
                DiagnosticRow(label: "Last key", value: format(model.lastEventAt))
                DiagnosticRow(label: "Last flush", value: "\(format(model.lastFlushAt)) / \(model.lastFlushEvents)")
                DiagnosticRow(label: "Restart", value: "\(format(model.lastRestartAt)) / \(model.restartCount)")
                DiagnosticRow(label: "Database", value: model.databasePath)
                DiagnosticRow(label: "Log", value: model.logPath)
            }
            .padding(.top, 6)
        }
    }

    private func format(_ date: Date?) -> String {
        guard let date else { return "none" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
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
            Text("If Keystats is already enabled but still cannot count, remove it from Input Monitoring and add it again.")
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

    var lockURL: URL {
        keystatsDirectory.appendingPathComponent("keystats-lite.lock")
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: keystatsDirectory, withIntermediateDirectories: true)
    }
}

enum SingleInstanceLockError: Error, CustomStringConvertible {
    case alreadyRunning
    case openFailed(String)
    case lockFailed(String)

    var description: String {
        switch self {
        case .alreadyRunning:
            return "Another Keystats instance is already running."
        case .openFailed(let path):
            return "Could not open lock file: \(path)"
        case .lockFailed(let message):
            return "Could not acquire app lock: \(message)"
        }
    }
}

enum KeystatsProcessScanner {
    struct ProcessInfo {
        let pid: pid_t
        let path: String
    }

    static func runningKeystatsProcesses() -> [ProcessInfo] {
        var processesByPID: [pid_t: ProcessInfo] = [:]

        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        if byteCount > 0 {
            let pidCount = Int(byteCount) / MemoryLayout<pid_t>.stride
            var pids = [pid_t](repeating: 0, count: pidCount)
            let actualByteCount = pids.withUnsafeMutableBytes { buffer in
                proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
            }
            if actualByteCount > 0 {
                let actualPIDCount = Int(actualByteCount) / MemoryLayout<pid_t>.stride
                for pid in pids.prefix(actualPIDCount) {
                    guard pid > 0,
                          let path = processPath(pid: pid),
                          isKeystatsPath(path) else {
                        continue
                    }
                    processesByPID[pid] = ProcessInfo(pid: pid, path: path)
                }
            }
        }

        for pid in pgrepKeystatsPIDs() where processesByPID[pid] == nil {
            let path = processPath(pid: pid)
            let command = processCommand(pid: pid)
            if isKeystatsPath(path) || isKeystatsCommand(command) {
                processesByPID[pid] = ProcessInfo(pid: pid, path: path ?? command ?? "unknown")
            }
        }

        return processesByPID.values.sorted { $0.pid < $1.pid }
    }

    static func isKeystatsPath(_ path: String?) -> Bool {
        guard let path else { return false }
        let lowercasedPath = path.lowercased()
        let executableName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if ["keystatslite", "keystats", "keystats-lite"].contains(executableName) {
            return true
        }
        return lowercasedPath.contains("/keystats.app/")
            || lowercasedPath.contains("/keystats lite.app/")
    }

    static func isRunning(pid: pid_t) -> Bool {
        processPath(pid: pid) != nil
    }

    static func processPath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func pgrepKeystatsPIDs() -> [pid_t] {
        run("/usr/bin/pgrep", arguments: ["-if", "keystats"])
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func isKeystatsCommand(_ command: String?) -> Bool {
        guard let command else { return false }
        let lowercasedCommand = command.lowercased()
        if lowercasedCommand.contains("/keystats.app/")
            || lowercasedCommand.contains("/keystats lite.app/")
            || lowercasedCommand.contains(".keystats/keystats.db")
            || lowercasedCommand.contains("keystats.db") {
            return true
        }
        let firstToken = lowercasedCommand.split(separator: " ").first.map(String.init)
        guard let firstToken else { return false }
        let executableName = URL(fileURLWithPath: firstToken).lastPathComponent
        return ["keystatslite", "keystats", "keystats-lite"].contains(executableName)
    }

    private static func processCommand(pid: pid_t) -> String? {
        let output = run("/bin/ps", arguments: ["-p", "\(pid)", "-o", "command="])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private static func run(_ executable: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

final class SingleInstanceLock {
    private let fileDescriptor: Int32

    init(url: URL, logger: LiteLogger) throws {
        logger.log("lock open path=\(url.path)")
        fileDescriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw SingleInstanceLockError.openFailed(url.path)
        }

        guard Self.acquire(fileDescriptor, url: url, logger: logger) else {
            let errorNumber = errno
            close(fileDescriptor)
            if errorNumber == EWOULDBLOCK {
                throw SingleInstanceLockError.alreadyRunning
            }
            throw SingleInstanceLockError.lockFailed(String(cString: strerror(errorNumber)))
        }

        ftruncate(fileDescriptor, 0)
        let pid = "\(ProcessInfo.processInfo.processIdentifier)\n"
        _ = pid.withCString { write(fileDescriptor, $0, strlen($0)) }
        logger.log("lock acquired path=\(url.path) pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    private static func acquire(_ fileDescriptor: Int32, url: URL, logger: LiteLogger) -> Bool {
        if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
            return true
        }

        guard errno == EWOULDBLOCK,
              let ownerPID = lockOwnerPID(url: url),
              ownerPID != ProcessInfo.processInfo.processIdentifier,
              isKeystatsProcess(pid: ownerPID) else {
            return false
        }

        logger.log("terminate lock owner pid=\(ownerPID) executable=\(KeystatsProcessScanner.processPath(pid: pid_t(ownerPID)) ?? "unknown")")
        kill(pid_t(ownerPID), SIGTERM)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        logger.log("force terminate lock owner pid=\(ownerPID)")
        kill(pid_t(ownerPID), SIGKILL)

        let forceDeadline = Date().addingTimeInterval(1)
        while Date() < forceDeadline {
            if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        return false
    }

    private static func lockOwnerPID(url: URL) -> Int? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return Int(contents.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func isKeystatsProcess(pid: Int) -> Bool {
        guard let path = KeystatsProcessScanner.processPath(pid: pid_t(pid)) else { return false }
        return URL(fileURLWithPath: path).lastPathComponent == "KeystatsLite"
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
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
