#if os(macOS)
import ApplicationServices
#endif

public struct PermissionStatus: Equatable {
    public let inputMonitoringGranted: Bool
    public let accessibilityGranted: Bool

    public init(inputMonitoringGranted: Bool, accessibilityGranted: Bool) {
        self.inputMonitoringGranted = inputMonitoringGranted
        self.accessibilityGranted = accessibilityGranted
    }
}

public protocol PermissionChecking {
    func status() -> PermissionStatus
    func requestInputMonitoringAccess() -> Bool
}

public struct PermissionChecker: PermissionChecking {
    public init() {}

    public func status() -> PermissionStatus {
        #if os(macOS)
        let inputMonitoring = CGPreflightListenEventAccess()
        let accessibility = AXIsProcessTrusted()
        return PermissionStatus(
            inputMonitoringGranted: inputMonitoring,
            accessibilityGranted: accessibility
        )
        #else
        return PermissionStatus(inputMonitoringGranted: false, accessibilityGranted: false)
        #endif
    }

    public func requestInputMonitoringAccess() -> Bool {
        #if os(macOS)
        return CGRequestListenEventAccess()
        #else
        return false
        #endif
    }
}
