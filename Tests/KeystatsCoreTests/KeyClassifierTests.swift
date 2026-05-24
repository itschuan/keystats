import KeystatsCore
import XCTest

final class KeyClassifierTests: XCTestCase {
    func testClassifiesCommonKeys() {
        let classifier = KeyClassifier()

        XCTAssertEqual(classifier.category(for: 0, displayName: "A"), .letter)
        XCTAssertEqual(classifier.category(for: 18, displayName: "1"), .number)
        XCTAssertEqual(classifier.category(for: 27, displayName: "-"), .symbol)
        XCTAssertEqual(classifier.category(for: 49, displayName: "Space"), .function)
        XCTAssertEqual(classifier.category(for: 55, displayName: "Command"), .modifier)
    }

    func testKeyboardLayoutResolverFallsBackToKeyCodeLabel() {
        let resolver = KeyboardLayoutResolver(fallbackNames: [:])

        XCTAssertEqual(resolver.displayName(for: 999), "Key 999")
    }
}

