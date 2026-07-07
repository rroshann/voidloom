import XCTest
@testable import VoidloomCore

final class WakePhraseMatcherTests: XCTestCase {
    private let matcher = WakePhraseMatcher(phrase: "hey voidloom")

    func testMatchFindsPhraseCaseInsensitive() {
        XCTAssertEqual(matcher.match(in: "Hey Voidloom start two agents"), "start two agents")
    }

    func testMatchReturnsEmptyWhenPhraseOnly() {
        XCTAssertEqual(matcher.match(in: "hey voidloom"), "")
    }

    func testMatchReturnsNilWhenPhraseAbsent() {
        XCTAssertNil(matcher.match(in: "start two agents"))
    }

    func testRollingScanFindsPhraseSplitAcrossFragments() {
        var buffer = ""
        XCTAssertNil(matcher.scanRolling(buffer: &buffer, appending: "hey void"))
        XCTAssertEqual(matcher.scanRolling(buffer: &buffer, appending: "loom spawn agent"), "spawn agent")
    }

    func testEmptyPhraseNeverMatches() {
        let empty = WakePhraseMatcher(phrase: "   ")
        XCTAssertNil(empty.match(in: "hey voidloom"))
    }
}
