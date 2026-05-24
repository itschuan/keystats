#if os(macOS)
import ApplicationServices
#endif
import Foundation

public final class KeyListener {
    public typealias Handler = (CapturedKeyEvent) -> Void

    private let appContextProvider: AppContextProviding
    private let layoutResolver: KeyboardLayoutResolver
    private let classifier: KeyClassifier

    public init(
        appContextProvider: AppContextProviding = AppContextProvider(),
        layoutResolver: KeyboardLayoutResolver = KeyboardLayoutResolver(),
        classifier: KeyClassifier = KeyClassifier()
    ) {
        self.appContextProvider = appContextProvider
        self.layoutResolver = layoutResolver
        self.classifier = classifier
    }

    public func event(fromKeyCode keyCode: Int, modifiers: Int = 0, timestamp: Date = Date()) -> CapturedKeyEvent {
        let name = layoutResolver.displayName(for: keyCode)
        let key = classifier.classify(keyCode: keyCode, displayName: name, modifiers: modifiers)
        return CapturedKeyEvent(timestamp: timestamp, key: key, app: appContextProvider.currentAppContext())
    }
}

