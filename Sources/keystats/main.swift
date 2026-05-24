import Foundation
import KeystatsCore

@main
struct KeystatsCLI {
    static func main() {
        do {
            try CommandRouter(arguments: Array(CommandLine.arguments.dropFirst())).run()
        } catch {
            fputs("Error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}

struct CommandRouter {
    let arguments: [String]
    let environment: CLIEnvironment

    init(arguments: [String], environment: CLIEnvironment = .default) {
        self.arguments = arguments
        self.environment = environment
    }

    func run() throws {
        let command = arguments.first ?? "help"
        let rest = Array(arguments.dropFirst())

        switch command {
        case "start":
            try StartCommand(environment: environment).run()
        case "stop":
            try StopCommand(environment: environment).run()
        case "pause":
            try StateCommand(environment: environment, status: .paused, message: "Keystats daemon paused.").run()
        case "resume":
            try StateCommand(environment: environment, status: .running, message: "Keystats daemon resumed.").run()
        case "status":
            try StatusCommand(environment: environment).run()
        case "doctor":
            DoctorCommand(environment: environment).run()
        case "today":
            try TodayCommand(environment: environment).run()
        case "week":
            try WeekCommand(environment: environment).run()
        case "stats":
            try StatsCommand(environment: environment, args: rest).run()
        case "keys":
            try KeysCommand(environment: environment, args: rest).run()
        case "mode":
            try ModeCommand(environment: environment, args: rest).run()
        case "clear":
            try ClearCommand(environment: environment, args: rest).run()
        case "daemon":
            try DaemonCommand(environment: environment, args: rest).run()
        default:
            HelpCommand().run()
        }
    }
}

struct CLIEnvironment {
    let homeDirectory: URL

    static var `default`: CLIEnvironment {
        CLIEnvironment(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    var keystatsDirectory: URL {
        homeDirectory.appendingPathComponent(".keystats", isDirectory: true)
    }

    var databaseURL: URL {
        keystatsDirectory.appendingPathComponent("keystats.db")
    }

    var logURL: URL {
        keystatsDirectory.appendingPathComponent("keystats.log")
    }

    var stateURL: URL {
        keystatsDirectory.appendingPathComponent("daemon.state.json")
    }

    var configURL: URL {
        keystatsDirectory.appendingPathComponent("config.json")
    }

    var launchAgentURL: URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("com.keystats.daemon.plist")
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: keystatsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func dataStore() throws -> SQLiteDataStore {
        try prepare()
        return try SQLiteDataStore(path: databaseURL.path)
    }
}

struct CLIConfig: Codable {
    var mode: StatsMode = .aggregate

    static func load(from url: URL) -> CLIConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(CLIConfig.self, from: data) else {
            return CLIConfig()
        }
        return config
    }

    func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}

struct DaemonState: Codable {
    var status: DaemonStatus
    var mode: StatsMode
    var updatedAt: Date

    static func load(from url: URL) -> DaemonState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DaemonState.self, from: data)
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

struct LaunchAgentManager {
    let environment: CLIEnvironment

    func install() throws {
        try environment.prepare()
        let executable = CommandLine.arguments[0]
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>com.keystats.daemon</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(executable)</string>
            <string>daemon</string>
            <string>run</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(environment.logURL.path)</string>
          <key>StandardErrorPath</key>
          <string>\(environment.logURL.path)</string>
        </dict>
        </plist>
        """
        try plist.write(to: environment.launchAgentURL, atomically: true, encoding: .utf8)
    }

    func uninstall() throws {
        if FileManager.default.fileExists(atPath: environment.launchAgentURL.path) {
            try FileManager.default.removeItem(at: environment.launchAgentURL)
        }
    }
}

struct StartCommand {
    let environment: CLIEnvironment

    func run() throws {
        let permission = PermissionChecker().status()
        guard permission.inputMonitoringGranted else {
            print("Input Monitoring: Not Granted")
            print("Open System Settings > Privacy & Security > Input Monitoring, then enable keystats.")
            return
        }

        try LaunchAgentManager(environment: environment).install()
        let config = CLIConfig.load(from: environment.configURL)
        try DaemonState(status: .running, mode: config.mode, updatedAt: Date()).save(to: environment.stateURL)
        print("Keystats daemon started.")
        print("Mode: \(config.mode.rawValue)")
    }
}

struct StopCommand {
    let environment: CLIEnvironment

    func run() throws {
        try LaunchAgentManager(environment: environment).uninstall()
        let config = CLIConfig.load(from: environment.configURL)
        try environment.prepare()
        try DaemonState(status: .stopped, mode: config.mode, updatedAt: Date()).save(to: environment.stateURL)
        print("Keystats daemon stopped.")
    }
}

struct StateCommand {
    let environment: CLIEnvironment
    let status: DaemonStatus
    let message: String

    func run() throws {
        try environment.prepare()
        let config = CLIConfig.load(from: environment.configURL)
        try DaemonState(status: status, mode: config.mode, updatedAt: Date()).save(to: environment.stateURL)
        print(message)
    }
}

struct StatusCommand {
    let environment: CLIEnvironment

    func run() throws {
        let state = DaemonState.load(from: environment.stateURL)
        let config = CLIConfig.load(from: environment.configURL)
        let store = try environment.dataStore()
        defer { store.close() }
        let today = try store.todayStats()

        print("Status: \(state?.status.rawValue ?? DaemonStatus.stopped.rawValue)")
        print("Mode: \(state?.mode.rawValue ?? config.mode.rawValue)")
        print("Today: \(today.totalKeys) keys")
    }
}

struct DoctorCommand {
    let environment: CLIEnvironment

    func run() {
        let status = PermissionChecker().status()
        print("Input Monitoring: \(status.inputMonitoringGranted ? "Granted" : "Not Granted")")
        print("Accessibility: \(status.accessibilityGranted ? "Granted" : "Not Granted")")
        print("Database: \(FileManager.default.fileExists(atPath: environment.databaseURL.path) ? environment.databaseURL.path : "Not initialized")")
        print("LaunchAgent: \(FileManager.default.fileExists(atPath: environment.launchAgentURL.path) ? "Installed" : "Not Installed")")
        if !status.inputMonitoringGranted {
            print("Open System Settings > Privacy & Security > Input Monitoring, then enable keystats.")
        }
    }
}

struct TodayCommand {
    let environment: CLIEnvironment

    func run() throws {
        let store = try environment.dataStore()
        defer { store.close() }
        let stats = try store.todayStats()
        print("Today's Stats")
        print("  Total Keys: \(stats.totalKeys)")
        print("  Active Time: \(stats.activeMinutes)m")
        if let peakHour = stats.peakHour {
            print(String(format: "  Peak Hour: %02d:00", peakHour))
        }
        if let topAppName = stats.topAppName {
            print("  Top App: \(topAppName)")
        }
    }
}

struct WeekCommand {
    let environment: CLIEnvironment

    func run() throws {
        let store = try environment.dataStore()
        defer { store.close() }
        let stats = try store.todayStats()
        print("Weekly Summary")
        print("  Today: \(stats.totalKeys)")
    }
}

struct StatsCommand {
    let environment: CLIEnvironment
    let args: [String]

    func run() throws {
        try TodayCommand(environment: environment).run()
        try KeysCommand(environment: environment, args: args).run()
    }
}

struct KeysCommand {
    let environment: CLIEnvironment
    let args: [String]

    func run() throws {
        let options = Options(args: args)
        let period = Period.parse(options.value(after: "--period") ?? "today")
        let category = options.value(after: "--category").flatMap(KeyCategory.init(rawValue:))
        let limit = options.value(after: "--limit").flatMap(Int.init) ?? 10
        let store = try environment.dataStore()
        defer { store.close() }
        let keys = try store.topKeys(
            period: period,
            appBundleID: options.value(after: "--app-bundle-id"),
            category: category,
            limit: limit
        )
        print("Top Keys")
        for key in keys {
            print("  \(key.keyName): \(key.count)")
        }
    }
}

struct ModeCommand {
    let environment: CLIEnvironment
    let args: [String]

    func run() throws {
        try environment.prepare()
        var config = CLIConfig.load(from: environment.configURL)
        guard let rawMode = args.first else {
            print("Current Mode: \(config.mode.rawValue)")
            return
        }

        guard let mode = StatsMode(rawValue: rawMode) else {
            print("Unknown mode: \(rawMode)")
            return
        }

        if mode == .detail && !args.contains("--confirm") {
            print("Warning: detail mode stores individual key events locally.")
            print("Run `keystats mode detail --confirm` to enable it.")
            return
        }

        config.mode = mode
        try config.save(to: environment.configURL)
        print("Mode: \(mode.rawValue)")
    }
}

struct ClearCommand {
    let environment: CLIEnvironment
    let args: [String]

    func run() throws {
        let options = Options(args: args)
        guard options.has("--confirm") else {
            print("This will delete stored data. Continue with --confirm.")
            return
        }
        let store = try environment.dataStore()
        defer { store.close() }
        if options.has("--detail") {
            try store.clearDetailEvents()
            print("Detail events cleared.")
        } else {
            try store.clearAllData()
            print("All local stats cleared.")
        }
    }
}

struct DaemonCommand {
    let environment: CLIEnvironment
    let args: [String]

    func run() throws {
        guard args.first == "run" else {
            print("Usage: keystats daemon run")
            return
        }
        try environment.prepare()
        let config = CLIConfig.load(from: environment.configURL)
        let permission = PermissionChecker().status()
        let status: DaemonStatus = permission.inputMonitoringGranted ? .running : .permissionRequired
        try DaemonState(status: status, mode: config.mode, updatedAt: Date()).save(to: environment.stateURL)
        RunLoop.current.run()
    }
}

struct HelpCommand {
    func run() {
        print(
            """
            Usage: keystats <command>

            Commands:
              start       Start daemon
              pause       Pause statistics
              resume      Resume statistics
              stop        Stop daemon
              status      Show daemon status
              doctor      Check permissions and storage
              today       Show today's stats
              week        Show weekly summary
              stats       Show detailed stats
              keys        Show top keys
              mode        Show or set statistics mode
              clear       Clear local data
            """
        )
    }
}

struct Options {
    let args: [String]

    func value(after key: String) -> String? {
        guard let index = args.firstIndex(of: key), args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
    }

    func has(_ key: String) -> Bool {
        args.contains(key)
    }
}

