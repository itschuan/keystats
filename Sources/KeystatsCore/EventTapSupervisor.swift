#if os(macOS)
import ApplicationServices
import AppKit
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
    public var hidKeyDownEvents: Int
    public var appKitKeyDownEvents: Int
    public var appKitGlobalKeyDownEvents: Int
    public var appKitLocalKeyDownEvents: Int
    public var tapDisabledEvents: Int
    public var lastEventType: String?
    public var lastKeyCode: Int?

    public static let empty = EventTapDiagnostics(
        location: .unavailable,
        keyDownEvents: 0,
        flagsChangedEvents: 0,
        hidKeyDownEvents: 0,
        appKitKeyDownEvents: 0,
        appKitGlobalKeyDownEvents: 0,
        appKitLocalKeyDownEvents: 0,
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
    private var hidManager: IOHIDManager?
    private var hidRunLoop: CFRunLoop?
    private var hidThread: Thread?
    private var appKitMonitors: [Any] = []
    private var activeModifierKeyCodes: Set<Int> = []
    private let diagnosticsLock = NSLock()
    private var eventTapDiagnostics = EventTapDiagnostics.empty
    private var lastRecordedKeyDown: (keyCode: Int, timestamp: Date)?
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
        stopHIDListener()
        stopAppKitListener()
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
        installHIDListener()
        installAppKitListener()
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
            recordKeyDownIfFresh(keyCode: keyCode, modifiers: Int(event.flags.rawValue))
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

    fileprivate func handleHIDValue(_ value: IOHIDValue) {
        guard status == .running else { return }
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == 0x07 else { return }
        guard IOHIDValueGetIntegerValue(value) != 0 else { return }

        let usage = Int(IOHIDElementGetUsage(element))
        guard !(224...231).contains(usage),
              let keyCode = Self.virtualKeyCodeByHIDUsage[usage] else {
            return
        }

        diagnosticsLock.lock()
        eventTapDiagnostics.hidKeyDownEvents += 1
        eventTapDiagnostics.lastEventType = "hidKeyDown"
        eventTapDiagnostics.lastKeyCode = keyCode
        diagnosticsLock.unlock()
        recordKeyDownIfFresh(keyCode: keyCode)
    }

    private func handleAppKitEvent(_ event: NSEvent, source: String) {
        guard status == .running else { return }
        let keyCode = Int(event.keyCode)
        diagnosticsLock.lock()
        eventTapDiagnostics.appKitKeyDownEvents += 1
        if source == "appKitGlobal" {
            eventTapDiagnostics.appKitGlobalKeyDownEvents += 1
        } else {
            eventTapDiagnostics.appKitLocalKeyDownEvents += 1
        }
        eventTapDiagnostics.lastEventType = source
        eventTapDiagnostics.lastKeyCode = keyCode
        diagnosticsLock.unlock()
        recordKeyDownIfFresh(keyCode: keyCode, modifiers: Int(event.modifierFlags.rawValue))
    }

    private func recordKeyDownIfFresh(keyCode: Int, modifiers: Int = 0) {
        let now = Date()
        diagnosticsLock.lock()
        if let lastRecordedKeyDown,
           lastRecordedKeyDown.keyCode == keyCode,
           now.timeIntervalSince(lastRecordedKeyDown.timestamp) < 0.03 {
            diagnosticsLock.unlock()
            return
        }
        lastRecordedKeyDown = (keyCode, now)
        diagnosticsLock.unlock()
        handler?(keyListener.event(fromKeyCode: keyCode, modifiers: modifiers, timestamp: now))
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

    private func installHIDListener() {
        guard hidManager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let keyboard: [String: Int] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ]
        let keypad: [String: Int] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, [keyboard as CFDictionary, keypad as CFDictionary] as CFArray)
        IOHIDManagerRegisterInputValueCallback(manager, hidValueCallback, Unmanaged.passUnretained(self).toOpaque())

        hidManager = manager
        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                semaphore.signal()
                return
            }
            guard let runLoop = CFRunLoopGetCurrent() else {
                semaphore.signal()
                return
            }
            self.hidRunLoop = runLoop
            IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            semaphore.signal()
            CFRunLoopRun()
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        thread.name = "KeystatsHIDKeyboard"
        hidThread = thread
        thread.start()
        _ = semaphore.wait(timeout: .now() + 2)
    }

    private func stopHIDListener() {
        if let hidRunLoop {
            CFRunLoopStop(hidRunLoop)
        }
        hidRunLoop = nil
        hidManager = nil
        hidThread = nil
    }

    private func installAppKitListener() {
        guard appKitMonitors.isEmpty else { return }
        let install = { [weak self] in
            guard let self, self.appKitMonitors.isEmpty else { return }
            if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
                self?.handleAppKitEvent(event, source: "appKitGlobal")
            }) {
                self.appKitMonitors.append(globalMonitor)
            }
            if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
                self?.handleAppKitEvent(event, source: "appKitLocal")
                return event
            }) {
                self.appKitMonitors.append(localMonitor)
            }
        }

        if Thread.isMainThread {
            install()
        } else {
            DispatchQueue.main.sync(execute: install)
        }
    }

    private func stopAppKitListener() {
        let monitors = appKitMonitors
        appKitMonitors.removeAll()
        let remove = {
            monitors.forEach { NSEvent.removeMonitor($0) }
        }
        if Thread.isMainThread {
            remove()
        } else {
            DispatchQueue.main.sync(execute: remove)
        }
    }

    private static let virtualKeyCodeByHIDUsage: [Int: Int] = [
        4: 0, 5: 11, 6: 8, 7: 2, 8: 14, 9: 3, 10: 5, 11: 4, 12: 34, 13: 38,
        14: 40, 15: 37, 16: 46, 17: 45, 18: 31, 19: 35, 20: 12, 21: 15, 22: 1,
        23: 17, 24: 32, 25: 9, 26: 13, 27: 7, 28: 16, 29: 6,
        30: 18, 31: 19, 32: 20, 33: 21, 34: 23, 35: 22, 36: 26, 37: 28, 38: 25,
        39: 29, 40: 36, 41: 53, 42: 51, 43: 48, 44: 49, 45: 27, 46: 24,
        47: 33, 48: 30, 49: 42, 51: 41, 52: 39, 53: 50, 54: 43, 55: 47, 56: 44,
        57: 57, 58: 122, 59: 120, 60: 99, 61: 118, 62: 96, 63: 97, 64: 98,
        65: 100, 66: 101, 67: 109, 68: 103, 69: 111, 76: 117, 79: 124, 80: 123,
        81: 125, 82: 126, 83: 71, 84: 75, 85: 67, 86: 78, 87: 69, 88: 76,
        89: 65, 90: 82, 91: 83, 92: 84, 93: 85, 94: 86, 95: 87, 96: 88,
        97: 89, 98: 91, 99: 92
    ]
    #endif
}

#if os(macOS)
private func hidValueCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard result == kIOReturnSuccess, let context else { return }
    let supervisor = Unmanaged<EventTapSupervisor>.fromOpaque(context).takeUnretainedValue()
    supervisor.handleHIDValue(value)
}

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
