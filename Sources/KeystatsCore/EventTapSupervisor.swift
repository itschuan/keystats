#if os(macOS)
import ApplicationServices
import IOKit
#endif
import Foundation

public enum EventTapLocation: String, Codable, Equatable {
    case hid
    case session
    case unavailable
}

public struct EventTapDiagnostics: Codable, Equatable {
    public var location: EventTapLocation
    public var keyDownEvents: Int
    public var flagsChangedEvents: Int
    public var tapDisabledEvents: Int
    public var lastEventType: String?
    public var lastKeyCode: Int?

    public static let empty = EventTapDiagnostics(
        location: .unavailable,
        keyDownEvents: 0,
        flagsChangedEvents: 0,
        tapDisabledEvents: 0,
        lastEventType: nil,
        lastKeyCode: nil
    )
}

public struct SecureInputStatus: Codable, Equatable {
    public var isEnabled: Bool
    public var pid: Int?
    public var isAvailable: Bool

    public static let unavailable = SecureInputStatus(isEnabled: false, pid: nil, isAvailable: false)
}

public enum SecureInputChecker {
    public static func status() -> SecureInputStatus {
        #if os(macOS)
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IOHIDSystem")
        guard entry != MACH_PORT_NULL else {
            return .unavailable
        }
        defer { IOObjectRelease(entry) }

        for propertyName in ["SecureInputPID", "SecureEventInputPID"] {
            guard let property = IORegistryEntryCreateCFProperty(
                entry,
                propertyName as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() else {
                continue
            }

            if let number = property as? NSNumber {
                let pid = number.intValue
                return SecureInputStatus(isEnabled: pid > 0, pid: pid > 0 ? Int(pid) : nil, isAvailable: true)
            }
        }

        return SecureInputStatus(isEnabled: false, pid: nil, isAvailable: true)
        #else
        return .unavailable
        #endif
    }
}

public final class EventTapSupervisor {
    public typealias Handler = (CapturedKeyEvent) -> Void

    private let permissionChecker: PermissionChecking
    private let keyListener: KeyListener
    private var handler: Handler?

    #if os(macOS)
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapRunLoop: CFRunLoop?
    private var eventTapThread: Thread?
    private var activeModifierKeyCodes: Set<Int> = []
    private let diagnosticsLock = NSLock()
    private var eventTapDiagnostics = EventTapDiagnostics.empty
    #endif

    public private(set) var status: ListenerStatus = .stopped

    public init(permissionChecker: PermissionChecking = PermissionChecker(), keyListener: KeyListener = KeyListener()) {
        self.permissionChecker = permissionChecker
        self.keyListener = keyListener
    }

    public func diagnostics() -> EventTapDiagnostics {
        #if os(macOS)
        diagnosticsLock.lock()
        defer { diagnosticsLock.unlock() }
        return eventTapDiagnostics
        #else
        return .empty
        #endif
    }

    public func requestPermission() -> Bool {
        permissionChecker.requestInputMonitoringAccess()
    }

    public func start(handler: Handler? = nil) -> ListenerStatus {
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

    public func resume() -> ListenerStatus {
        start(handler: handler)
    }

    public func stop() {
        #if os(macOS)
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource, let eventTapRunLoop {
            CFRunLoopRemoveSource(eventTapRunLoop, runLoopSource, .commonModes)
            CFRunLoopStop(eventTapRunLoop)
        }
        runLoopSource = nil
        eventTap = nil
        eventTapRunLoop = nil
        eventTapThread = nil
        activeModifierKeyCodes.removeAll()
        diagnosticsLock.lock()
        eventTapDiagnostics.location = .unavailable
        diagnosticsLock.unlock()
        #endif
        handler = nil
        status = .stopped
    }

    #if os(macOS)
    private func installEventTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let (tap, location) = createEventTap(mask: mask) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        eventTap = tap
        runLoopSource = source
        diagnosticsLock.lock()
        eventTapDiagnostics.location = location
        diagnosticsLock.unlock()
        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                semaphore.signal()
                return
            }
            self.eventTapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            semaphore.signal()
            CFRunLoopRun()
        }
        thread.name = "KeystatsEventTap"
        eventTapThread = thread
        thread.start()
        return semaphore.wait(timeout: .now() + 2) == .success
    }

    private func createEventTap(mask: CGEventMask) -> (CFMachPort, EventTapLocation)? {
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) {
            return (tap, .hid)
        }

        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) {
            return (tap, .session)
        }

        return nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        guard status == .running else { return }
        guard type == .keyDown || type == .flagsChanged else { return }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        recordDiagnosticEvent(type: type, keyCode: keyCode)
        if type == .keyDown {
            handler?(keyListener.event(fromKeyCode: keyCode, modifiers: Int(event.flags.rawValue)))
            return
        }
        if type == .flagsChanged {
            if activeModifierKeyCodes.contains(keyCode) {
                activeModifierKeyCodes.remove(keyCode)
                return
            }
            activeModifierKeyCodes.insert(keyCode)
        }
        let modifiers = Int(event.flags.rawValue)
        handler?(keyListener.event(fromKeyCode: keyCode, modifiers: modifiers))
    }

    private func recordDiagnosticEvent(type: CGEventType, keyCode: Int) {
        diagnosticsLock.lock()
        if type == .keyDown {
            eventTapDiagnostics.keyDownEvents += 1
        } else if type == .flagsChanged {
            eventTapDiagnostics.flagsChangedEvents += 1
        }
        eventTapDiagnostics.lastEventType = type == .keyDown ? "keyDown" : "flagsChanged"
        eventTapDiagnostics.lastKeyCode = keyCode
        diagnosticsLock.unlock()
    }

    fileprivate func reenableEventTap() {
        diagnosticsLock.lock()
        eventTapDiagnostics.tapDisabledEvents += 1
        diagnosticsLock.unlock()
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
