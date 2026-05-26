import KeystatsCore
import XCTest

final class EventTapSupervisorTests: XCTestCase {
    func testStartRequiresPermission() {
        let supervisor = EventTapSupervisor(permissionChecker: StubPermissionChecker(granted: false))

        XCTAssertEqual(supervisor.start(), .permissionRequired)
    }

    func testPauseAndResume() {
        let supervisor = EventTapSupervisor(permissionChecker: StubPermissionChecker(granted: true))

        XCTAssertEqual(supervisor.start(), .running)
        supervisor.pause()
        XCTAssertEqual(supervisor.status, .paused)
        XCTAssertEqual(supervisor.resume(), .running)
    }
}

private struct StubPermissionChecker: PermissionChecking {
    let granted: Bool

    func status() -> PermissionStatus {
        PermissionStatus(inputMonitoringGranted: granted, accessibilityGranted: granted)
    }

    func requestInputMonitoringAccess() -> Bool {
        granted
    }
}
