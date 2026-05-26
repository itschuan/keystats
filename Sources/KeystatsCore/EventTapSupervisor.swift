#if os(macOS)
import ApplicationServices
#endif
import Foundation

public final class EventTapSupervisor {
    public typealias Handler = (CapturedKeyEvent) -> Void

    private let permissionChecker: PermissionChecking
    private let keyListener: KeyListener
    private var handler: Handler?

    #if os(macOS)
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    #endif

    public private(set) var status: DaemonStatus = .stopped

    public init(permissionChecker: PermissionChecking = PermissionChecker(), keyListener: KeyListener = KeyListener()) {
        self.permissionChecker = permissionChecker
        self.keyListener = keyListener
    }

    public func requestPermission() -> Bool {
        permissionChecker.requestInputMonitoringAccess()
    }

    public func start(handler: Handler? = nil) -> DaemonStatus {
        self.handler = handler

        #if os(macOS)
        if handler == nil && !permissionChecker.status().inputMonitoringGranted {
            status = .permissionRequired
            return status
        }
        if eventTap == nil && handler != nil {
            guard installEventTap() else {
                if !permissionChecker.status().inputMonitoringGranted {
                    status = .permissionRequired
                    return status
                }
                status = .error
                return status
            }
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        #else
        guard permissionChecker.status().inputMonitoringGranted else {
            status = .permissionRequired
            return status
        }
        #endif

        status = .running
        return status
    }

    public func pause() {
        if status == .running {
            #if os(macOS)
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: false)
            }
            #endif
            status = .paused
        }
    }

    public func resume() -> DaemonStatus {
        start(handler: handler)
    }

    public func stop() {
        #if os(macOS)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        #endif
        handler = nil
        status = .stopped
    }

    #if os(macOS)
    private func installEventTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        guard status == .running else { return }
        guard type == .keyDown || type == .flagsChanged else { return }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = Int(event.flags.rawValue)
        handler?(keyListener.event(fromKeyCode: keyCode, modifiers: modifiers))
    }

    fileprivate func reenableEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }
    #endif
}

#if os(macOS)
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let supervisor = Unmanaged<EventTapSupervisor>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        supervisor.reenableEventTap()
    } else {
        supervisor.handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
#endif
