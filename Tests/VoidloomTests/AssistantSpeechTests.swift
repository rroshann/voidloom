import XCTest
@testable import VoidloomCore

final class AssistantSpeechTests: XCTestCase {
    func testShortReplyIsSpokenWhole() {
        XCTAssertEqual(AssistantSpeech.spoken(from: "Spawned 2 agents: ember, slate"),
                       "Spawned 2 agents: ember, slate")
    }

    func testLongReplyIsTrimmedToTwoSentencesWithPointer() {
        let text = "First point. Second point. Third point. Fourth point."
        let spoken = AssistantSpeech.spoken(from: text)
        XCTAssertEqual(spoken, "First point. Second point. There's more on screen.")
    }

    func testCodeAndMarkdownAreStrippedForSpeech() {
        let text = "Here is how:\n```swift\nlet x = 1\n```\nUse **bold** and `code`."
        let spoken = AssistantSpeech.spoken(from: text)
        XCTAssertFalse(spoken.contains("```"))
        XCTAssertFalse(spoken.contains("`"))
        XCTAssertFalse(spoken.contains("*"))
        XCTAssertTrue(spoken.contains("bold"))
    }

    func testMarkdownLinkSpeaksLabelNotURL() {
        let text = "Check the [release notes](https://github.com/rroshann/voidloom/releases)."
        let spoken = AssistantSpeech.spoken(from: text)
        XCTAssertTrue(spoken.contains("release notes"))
        XCTAssertFalse(spoken.contains("http"))
        XCTAssertFalse(spoken.contains("]"))
        XCTAssertFalse(spoken.contains(")"))
    }

    func testBareURLBecomesShortWord() {
        let text = "See https://example.com/very/long/path?q=1 for details."
        let spoken = AssistantSpeech.spoken(from: text)
        XCTAssertFalse(spoken.contains("http"))
        XCTAssertFalse(spoken.contains("example.com"))
        XCTAssertTrue(spoken.contains("a link"))
    }

    func testFilePathSpeaksBasenameOnly() {
        let text = "I edited VoidloomApp/Spaces/SpacesShellView.swift for you."
        let spoken = AssistantSpeech.spoken(from: text)
        XCTAssertTrue(spoken.contains("SpacesShellView.swift"))
        XCTAssertFalse(spoken.contains("VoidloomApp"))
        XCTAssertFalse(spoken.contains("/"))
    }

    func testNonPathSlashesSurvive() {
        // Natural-language slashes must not be mangled into a "basename".
        let spoken = AssistantSpeech.spoken(from: "Pick one and/or the other.")
        XCTAssertTrue(spoken.contains("and/or"))
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(AssistantSpeech.spoken(from: "   "), "")
    }
}
