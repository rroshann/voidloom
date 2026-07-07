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

    func testEmptyStaysEmpty() {
        XCTAssertEqual(AssistantSpeech.spoken(from: "   "), "")
    }
}
