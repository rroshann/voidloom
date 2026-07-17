import Testing
@testable import VoidloomCore

@Suite struct ReplyValidatorTests {
    @Test func forbiddenNameNotLiveIsFlagged() {
        let v = ReplyValidator.validate(
            reply: "I can run the ember or nova terminals.",
            knownTitles: ["my ideas"]
        )
        #expect(v.isGrounded == false)
    }

    @Test func forbiddenNameThatIsLiveIsFine() {
        let v = ReplyValidator.validate(
            reply: "ember is running your build.",
            knownTitles: ["ember"]
        )
        #expect(v.isGrounded == true)
    }

    @Test func unknownNamePlusKindNounIsFlagged() {
        let v = ReplyValidator.validate(reply: "Look at the Juno note.", knownTitles: [])
        #expect(v.isGrounded == false)
        #expect(v.offendingNames.contains("Juno"))
    }

    @Test func genericPhrasingNeverFlags() {
        let v = ReplyValidator.validate(
            reply: "I made a note for you. The note is on page 2.",
            knownTitles: ["my ideas"]
        )
        #expect(v.isGrounded == true)
    }

    @Test func liveTitleMentionIsFineCaseInsensitive() {
        let v = ReplyValidator.validate(
            reply: "Your My Ideas note is ready.",
            knownTitles: ["my ideas"]
        )
        #expect(v.isGrounded == true)
    }

    @Test @MainActor func groundedRepliesEmptyVariesAndIsNonEmpty() {
        let a = GroundedReplies.fallback(cardTitles: [], workspaceName: "QA")
        #expect(a.isEmpty == false)
        #expect(GroundedReplies.fallback(cardTitles: [], workspaceName: "QA") != a)
    }

    @Test @MainActor func groundedRepliesMentionsRealTitles() {
        let reply = GroundedReplies.fallback(cardTitles: ["my ideas"], workspaceName: "QA")
        #expect(reply.contains("my ideas"))
    }

    @Test func personaHasAntiEchoRule() {
        #expect(AssistantIdentity.systemPrompt().contains("Never repeat your previous reply verbatim"))
    }

    @Test func defaultForbiddenIncludesPoolAndSchemaNames() {
        let expected: Set<String> = [
            "ember", "slate", "nova", "drift", "ridge", "quartz", "scout", "juno",
        ]
        #expect(expected.isSubset(of: ReplyValidator.defaultForbidden))
    }
}
