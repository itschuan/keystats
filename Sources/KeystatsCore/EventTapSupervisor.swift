import Foundation

public final class EventTapSupervisor {
    private let permissionChecker: PermissionChecking
    public private(set) var status: DaemonStatus = .stopped

    public init(permissionChecker: PermissionChecking = PermissionChecker()) {
        self.permissionChecker = permissionChecker
    }

    public func start() -> DaemonStatus {
        guard permissionChecker.status().inputMonitoringGranted else {
            status = .permissionRequired
            return status
        }
        status = .running
        return status
    }

    public func pause() {
        if status == .running {
            status = .paused
        }
    }

    public func resume() -> DaemonStatus {
        start()
    }

    public func stop() {
        status = .stopped
    }
}

