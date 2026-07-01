import XCTest
@testable import VoidloomCore

final class MediatorCommandTests: XCTestCase {
    private func roundTrip(_ command: MediatorCommand) throws -> MediatorCommand {
        let data = try JSONEncoder().encode(command)
        return try JSONDecoder().decode(MediatorCommand.self, from: data)
    }

    func testEveryCaseRoundTripsThroughCodable() throws {
        let commands: [MediatorCommand] = [
            .spawnAgents(count: 4, kind: .claudeCode, names: nil),
            .spawnAgents(count: 2, kind: .shell, names: ["viper", "sage"]),
            .sendPrompt(target: "jerry", text: "look into the API errors"),
            .readOutput(target: "viper"),
            .closeTerminal(target: "omen"),
            .arrange(style: .grid),
            .arrange(style: .focus(target: "sage")),
            .createCard(kind: .note, content: "standup notes"),
            .createCard(kind: .todo, content: nil),
            .switchSpace(name: "voidloom"),
            .setBackground(spec: .atmosphere),
            .setBackground(spec: .solid(hex: "#102030FF")),
        ]
        for command in commands {
            XCTAssertEqual(try roundTrip(command), command)
        }
    }

    func testWireFormatIsStableForBrainGrammars() throws {
        // Later plans generate grammars against exactly this shape — a failure
        // here means the brain contract changed and grammars must be regenerated.
        let json = #"{"sendPrompt":{"target":"jerry","text":"hi"}}"#
        let decoded = try JSONDecoder().decode(MediatorCommand.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, .sendPrompt(target: "jerry", text: "hi"))
    }
}
