import XCTest
@testable import VoidloomCore

final class WorkspaceContextBuilderTests: XCTestCase {
    private func snapshot(
        name: String = "QA",
        mode: String = "Spaces",
        folder: String? = "/Users/me/dev/dungeness",
        git: String? = "master, clean",
        brain: String? = "fast path + local LLM + Apple Intelligence",
        cards: [WorkspaceContextBuilder.CardLine] = [],
        recent: String? = nil,
        selected: String? = nil
    ) -> WorkspaceContextBuilder.Snapshot {
        WorkspaceContextBuilder.Snapshot(
            workspaceName: name, mode: mode, folderPath: folder, gitSummary: git,
            brainTier: brain, cards: cards, recentActivity: recent, selectedCardContext: selected)
    }

    func testBuildsHeaderWorkspaceFolderAndGit() {
        let out = WorkspaceContextBuilder.build(snapshot(cards: [
            .init(title: "ember", kind: "terminal", detail: "running"),
        ]))
        XCTAssertTrue(out.contains("[Voidloom workspace context]"))
        XCTAssertTrue(out.contains("Workspace: \"QA\" (Spaces mode)"))
        XCTAssertTrue(out.contains("/Users/me/dev/dungeness"))
        XCTAssertTrue(out.contains("git: master, clean"))
        XCTAssertTrue(out.contains("- ember — terminal, running"))
    }

    func testEmptyWorkspaceStatesNoCardsAndOmitsMissingSections() {
        let out = WorkspaceContextBuilder.build(snapshot(folder: nil, git: nil, cards: []))
        XCTAssertTrue(out.contains("Cards: none"))
        XCTAssertFalse(out.contains("Folder:"))
        XCTAssertFalse(out.contains("git:"))
    }

    func testCardListIsCappedWithRemainderCount() {
        let cards = (1...30).map { WorkspaceContextBuilder.CardLine(title: "c\($0)", kind: "note", detail: nil) }
        let out = WorkspaceContextBuilder.build(snapshot(git: nil, cards: cards))
        XCTAssertTrue(out.contains("Cards (30):"))
        XCTAssertTrue(out.contains("- c1 — note"))
        XCTAssertTrue(out.contains("- c\(WorkspaceContextBuilder.maxCards) — note"))
        XCTAssertFalse(out.contains("- c\(WorkspaceContextBuilder.maxCards + 1) — note"))
        XCTAssertTrue(out.contains("…and \(30 - WorkspaceContextBuilder.maxCards) more"))
    }

    func testCardDetailIsAppendedWhenPresent() {
        let out = WorkspaceContextBuilder.build(snapshot(cards: [
            .init(title: "Notes", kind: "note", detail: "qa checklist in progress"),
            .init(title: "Git", kind: "git", detail: nil),
        ]))
        XCTAssertTrue(out.contains("- Notes — note: qa checklist in progress"))
        XCTAssertTrue(out.contains("- Git — git\n") || out.hasSuffix("- Git — git"))
    }

    func testSelectedCardContextIsIncludedLast() {
        let out = WorkspaceContextBuilder.build(snapshot(selected: "New Note\nremember to ship"))
        XCTAssertTrue(out.contains("Selected card:"))
        XCTAssertTrue(out.contains("remember to ship"))
    }

    func testOutputNeverExceedsHardCharacterCap() {
        let cards = (1...20).map {
            WorkspaceContextBuilder.CardLine(title: "card\($0)", kind: "note",
                detail: String(repeating: "x", count: 400))
        }
        let out = WorkspaceContextBuilder.build(snapshot(cards: cards, selected: String(repeating: "y", count: 5000)))
        XCTAssertLessThanOrEqual(out.count, WorkspaceContextBuilder.maxCharacters)
        XCTAssertTrue(out.contains("[Voidloom workspace context]"), "header must survive truncation")
    }

    func testNoteDetailCollapsesToFirstLine() {
        let out = WorkspaceContextBuilder.build(snapshot(cards: [
            .init(title: "N", kind: "note", detail: "first line\nsecond line\nthird"),
        ]))
        XCTAssertTrue(out.contains("- N — note: first line"))
        XCTAssertFalse(out.contains("second line"))
    }
}
