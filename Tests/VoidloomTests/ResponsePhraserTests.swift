import Testing
@testable import VoidloomCore

@Suite struct ResponsePhraserTests {
    @Test func sentenceSplitter() {
        #expect(SentenceSplitter.split("One. Two! Three?") == ["One.", "Two!", "Three?"])
        #expect(SentenceSplitter.split("No terminator") == ["No terminator"])
    }

    @Test func responsePhraserPrompts() {
        let sys = ResponsePhraser.systemPrompt()
        #expect(sys.contains("only the given facts") || sys.lowercased().contains("invent nothing") || sys.lowercased().contains("no invention"))
        #expect(!sys.contains("ember") && !sys.contains("slate"))

        let user = ResponsePhraser.userPrompt(fact: "Created a note", context: "[Voidloom workspace context]\nCards: none")
        #expect(user.contains("Created a note") && user.contains("Cards: none"))
    }

    @Test func sanitize() {
        #expect(ResponsePhraser.sanitize("  \"Your note's up!\"  ", fallback: "f") == "Your note's up!")
        #expect(ResponsePhraser.sanitize("A. B. C. D.", fallback: "f") == "A. B.")
        #expect(ResponsePhraser.sanitize("   \n ", fallback: "Created a note") == "Created a note")
    }

    @Test @MainActor func assistantAcks() {
        #expect(AssistantAcks.pool.count >= 4)
        let a = AssistantAcks.next()
        #expect(AssistantAcks.next() != a)
    }

    @Test func groundingRulesPresent() {
        let prompt = AssistantIdentity.systemPrompt()
        #expect(prompt.contains("Cards: none") && prompt.contains("placeholders"))
    }
}
