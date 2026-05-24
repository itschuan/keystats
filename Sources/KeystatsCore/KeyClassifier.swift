import Foundation

public struct KeyClassifier {
    public init() {}

    public func classify(keyCode: Int, displayName: String, modifiers: Int = 0) -> KeyDescriptor {
        KeyDescriptor(
            keyCode: keyCode,
            keyName: displayName,
            category: category(for: keyCode, displayName: displayName),
            modifiers: modifiers
        )
    }

    public func category(for keyCode: Int, displayName: String) -> KeyCategory {
        if Self.modifierKeyCodes.contains(keyCode) {
            return .modifier
        }

        if Self.functionKeyCodes.contains(keyCode) || displayName.uppercased().hasPrefix("F") && displayName.dropFirst().allSatisfy(\.isNumber) {
            return .function
        }

        if displayName.count == 1 {
            let scalar = displayName.unicodeScalars.first
            if let scalar, CharacterSet.letters.contains(scalar) {
                return .letter
            }
            if let scalar, CharacterSet.decimalDigits.contains(scalar) {
                return .number
            }
            if let scalar, CharacterSet.punctuationCharacters.union(.symbols).contains(scalar) {
                return .symbol
            }
        }

        switch displayName.lowercased() {
        case "space", "tab", "return", "enter", "delete", "backspace", "escape":
            return .function
        default:
            return .other
        }
    }

    private static let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62]
    private static let functionKeyCodes: Set<Int> = [
        36, 48, 49, 51, 53, 71, 76,
        96, 97, 98, 99, 100, 101, 103, 105, 106, 107, 109, 111, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126
    ]
}

