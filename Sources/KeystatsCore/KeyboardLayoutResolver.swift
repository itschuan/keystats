import Foundation

public struct KeyboardLayoutResolver {
    private let fallbackNames: [Int: String]

    public init(fallbackNames: [Int: String] = KeyboardLayoutResolver.defaultUSKeyNames) {
        self.fallbackNames = fallbackNames
    }

    public func displayName(for keyCode: Int) -> String {
        fallbackNames[keyCode] ?? "Key \(keyCode)"
    }

    public static let defaultUSKeyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        51: "Delete", 53: "Escape", 55: "Command", 56: "Shift", 57: "CapsLock",
        58: "Option", 59: "Control", 60: "RightShift", 61: "RightOption",
        62: "RightControl", 63: "Function", 123: "Left", 124: "Right",
        125: "Down", 126: "Up"
    ]
}

