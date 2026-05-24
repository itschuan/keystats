#if os(macOS)
import AppKit
#endif

public protocol AppContextProviding {
    func currentAppContext() -> AppContext
}

public struct AppContextProvider: AppContextProviding {
    public init() {}

    public func currentAppContext() -> AppContext {
        #if os(macOS)
        let app = NSWorkspace.shared.frontmostApplication
        return AppContext(bundleID: app?.bundleIdentifier, name: app?.localizedName)
        #else
        return .unknown
        #endif
    }
}

