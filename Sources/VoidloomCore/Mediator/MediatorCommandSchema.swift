import Foundation

/// The frozen wire contract for `MediatorCommand`. Plan 2b generates the
/// llama.cpp GBNF grammar from `cases`, and tier-1 tool definitions are
/// parity-tested against it; `samples` are the freeze fixtures proving the
/// descriptor and Swift's synthesized Codable cannot drift apart.
/// Decision (2026-07-02): `.grid` and `.retile` stay DISTINCT wire cases —
/// identical behavior today, expected to diverge (grid may force `.auto`
/// tiling; re-tile re-derives the current mode).
public enum MediatorCommandSchema {
    public struct Parameter: Equatable, Sendable {
        public enum Kind: String, Sendable {
            case string, integer, bool, stringArray, agentKind, arrangeStyle, cardKind, backgroundSpec
        }
        public let name: String
        public let kind: Kind
        public let required: Bool

        public init(name: String, kind: Kind, required: Bool) {
            self.name = name; self.kind = kind; self.required = required
        }
    }

    public struct Case: Equatable, Sendable {
        public let name: String
        public let parameters: [Parameter]

        public init(name: String, parameters: [Parameter]) {
            self.name = name; self.parameters = parameters
        }
    }

    public static let cases: [Case] = [
        Case(name: "spawnAgents", parameters: [
            Parameter(name: "count", kind: .integer, required: true),
            Parameter(name: "kind", kind: .agentKind, required: true),
            Parameter(name: "names", kind: .stringArray, required: false),
        ]),
        Case(name: "sendPrompt", parameters: [
            Parameter(name: "target", kind: .string, required: true),
            Parameter(name: "text", kind: .string, required: true),
        ]),
        Case(name: "readOutput", parameters: [
            Parameter(name: "target", kind: .string, required: true),
        ]),
        Case(name: "closeTerminal", parameters: [
            Parameter(name: "target", kind: .string, required: true),
        ]),
        Case(name: "arrange", parameters: [
            Parameter(name: "style", kind: .arrangeStyle, required: true),
        ]),
        Case(name: "createCard", parameters: [
            Parameter(name: "kind", kind: .cardKind, required: true),
            Parameter(name: "content", kind: .string, required: false),
        ]),
        Case(name: "switchSpace", parameters: [
            Parameter(name: "name", kind: .string, required: true),
        ]),
        Case(name: "setBackground", parameters: [
            Parameter(name: "spec", kind: .backgroundSpec, required: true),
        ]),
        Case(name: "renameCard", parameters: [
            Parameter(name: "target", kind: .string, required: true),
            Parameter(name: "newName", kind: .string, required: true),
        ]),
        Case(name: "deleteCard", parameters: [
            Parameter(name: "target", kind: .string, required: true),
        ]),
        Case(name: "editNote", parameters: [
            Parameter(name: "target", kind: .string, required: true),
            Parameter(name: "content", kind: .string, required: true),
            Parameter(name: "append", kind: .bool, required: true),
        ]),
        Case(name: "addTodoItem", parameters: [
            Parameter(name: "target", kind: .string, required: true),
            Parameter(name: "text", kind: .string, required: true),
        ]),
        Case(name: "setTodoItemDone", parameters: [
            Parameter(name: "target", kind: .string, required: true),
            Parameter(name: "text", kind: .string, required: true),
            Parameter(name: "done", kind: .bool, required: true),
        ]),
        Case(name: "delegate", parameters: [
            Parameter(name: "question", kind: .string, required: true),
            Parameter(name: "target", kind: .string, required: false),
        ]),
    ]

    /// One canonical wire sample per case. Every sample must decode into
    /// `MediatorCommand` and re-encode under the same top-level key (tested).
    public static let samples: [String: String] = [
        "spawnAgents": #"{"spawnAgents":{"count":2,"kind":"claude","names":["ember","slate"]}}"#,
        "sendPrompt": #"{"sendPrompt":{"target":"ember","text":"fix the build"}}"#,
        "readOutput": #"{"readOutput":{"target":"ember"}}"#,
        "closeTerminal": #"{"closeTerminal":{"target":"ember"}}"#,
        "arrange": #"{"arrange":{"style":{"focus":{"target":"ember"}}}}"#,
        "createCard": #"{"createCard":{"kind":"note","content":"standup"}}"#,
        "switchSpace": #"{"switchSpace":{"name":"research"}}"#,
        "setBackground": ##"{"setBackground":{"spec":{"solid":{"hex":"#102030FF"}}}}"##,
        "renameCard": #"{"renameCard":{"target":"ember","newName":"scout"}}"#,
        "deleteCard": #"{"deleteCard":{"target":"standup"}}"#,
        "editNote": #"{"editNote":{"target":"standup","content":"ship it","append":true}}"#,
        "addTodoItem": #"{"addTodoItem":{"target":"chores","text":"buy milk"}}"#,
        "setTodoItemDone": #"{"setTodoItemDone":{"target":"chores","text":"buy milk","done":true}}"#,
        "delegate": #"{"delegate":{"question":"how does persistence work","target":"ember"}}"#,
    ]

    /// Allowed values for `.agentKind` parameters — the grammar constrains
    /// `spawnAgents.kind` to exactly these instead of an arbitrary string.
    public static let agentKindValues: [String] = MediatorAgentKind.allCases.map(\.rawValue)
}
