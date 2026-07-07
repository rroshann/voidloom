import Foundation
import FoundationModels
import VoidloomCore

/// Tier-1 `@Generable` mirrors of `MediatorCommand`. Core cannot import
/// FoundationModels, so these live in the app layer and are parity-tested
/// against `MediatorCommandSchema` (the frozen wire contract).
@available(macOS 26, *)
enum MediatorToolMirrors {
    /// Every `MediatorCommandSchema.cases` name — parity tests assert bijection.
    static let mirrorCaseNames: [String] = [
        "spawnAgents", "sendPrompt", "readOutput", "closeTerminal",
        "arrange", "createCard", "switchSpace", "setBackground",
        "renameCard", "deleteCard", "editNote", "addTodoItem", "setTodoItemDone",
        "delegate",
    ]

    /// Canonical mirror instance per schema sample (for round-trip parity tests).
    static func sampleMirror(named caseName: String) -> (any MediatorCommandMirroring)? {
        switch caseName {
        case "spawnAgents":
            return SpawnAgentsMirror(count: 2, kind: "claude", names: ["ember", "slate"])
        case "sendPrompt":
            return SendPromptMirror(target: "ember", text: "fix the build")
        case "readOutput":
            return ReadOutputMirror(target: "ember")
        case "closeTerminal":
            return CloseTerminalMirror(target: "ember")
        case "arrange":
            return ArrangeMirror(style: ArrangeStyleMirror(focus: FocusStyleMirror(target: "ember")))
        case "createCard":
            return CreateCardMirror(kind: "note", content: "standup")
        case "switchSpace":
            return SwitchSpaceMirror(name: "research")
        case "setBackground":
            return SetBackgroundMirror(spec: BackgroundSpecMirror(solid: SolidBackgroundMirror(hex: "#102030FF")))
        case "renameCard":
            return RenameCardMirror(target: "ember", newName: "scout")
        case "deleteCard":
            return DeleteCardMirror(target: "standup")
        case "editNote":
            return EditNoteMirror(target: "standup", content: "ship it", append: true)
        case "addTodoItem":
            return AddTodoItemMirror(target: "chores", text: "buy milk")
        case "setTodoItemDone":
            return SetTodoItemDoneMirror(target: "chores", text: "buy milk", done: true)
        case "delegate":
            return DelegateMirror(question: "how does persistence work", target: "ember")
        default:
            return nil
        }
    }
}

@available(macOS 26, *)
protocol MediatorCommandMirroring {
    func toCommand() throws -> MediatorCommand
}

// MARK: - Nested wire shapes

@available(macOS 26, *)
@Generable
struct EmptyObjectMirror {}

@available(macOS 26, *)
@Generable
struct FocusStyleMirror {
    var target: String
}

@available(macOS 26, *)
@Generable
struct ArrangeStyleMirror {
    var grid: EmptyObjectMirror?
    var retile: EmptyObjectMirror?
    var focus: FocusStyleMirror?
}

@available(macOS 26, *)
@Generable
struct SolidBackgroundMirror {
    var hex: String
}

@available(macOS 26, *)
@Generable
struct BackgroundSpecMirror {
    var atmosphere: EmptyObjectMirror?
    var solid: SolidBackgroundMirror?
}

// MARK: - Per-case mirrors

@available(macOS 26, *)
@Generable
struct SpawnAgentsMirror: MediatorCommandMirroring {
    var count: Int
    @Guide(.anyOf(MediatorCommandSchema.agentKindValues))
    var kind: String
    var names: [String]?

    func toCommand() throws -> MediatorCommand {
        guard let agentKind = MediatorAgentKind(rawValue: kind) else {
            throw MirrorConversionError.invalidAgentKind(kind)
        }
        return .spawnAgents(count: count, kind: agentKind, names: names)
    }
}

@available(macOS 26, *)
@Generable
struct SendPromptMirror: MediatorCommandMirroring {
    var target: String
    var text: String

    func toCommand() throws -> MediatorCommand {
        .sendPrompt(target: target, text: text)
    }
}

@available(macOS 26, *)
@Generable
struct ReadOutputMirror: MediatorCommandMirroring {
    var target: String

    func toCommand() throws -> MediatorCommand {
        .readOutput(target: target)
    }
}

@available(macOS 26, *)
@Generable
struct CloseTerminalMirror: MediatorCommandMirroring {
    var target: String

    func toCommand() throws -> MediatorCommand {
        .closeTerminal(target: target)
    }
}

@available(macOS 26, *)
@Generable
struct ArrangeMirror: MediatorCommandMirroring {
    var style: ArrangeStyleMirror

    func toCommand() throws -> MediatorCommand {
        .arrange(style: try style.toArrangeStyle())
    }
}

@available(macOS 26, *)
@Generable
struct CreateCardMirror: MediatorCommandMirroring {
    @Guide(.anyOf(CardKind.allCases.map(\.rawValue)))
    var kind: String
    var content: String?

    func toCommand() throws -> MediatorCommand {
        guard let cardKind = CardKind(rawValue: kind) else {
            throw MirrorConversionError.invalidCardKind(kind)
        }
        return .createCard(kind: cardKind, content: content)
    }
}

@available(macOS 26, *)
@Generable
struct SwitchSpaceMirror: MediatorCommandMirroring {
    var name: String

    func toCommand() throws -> MediatorCommand {
        .switchSpace(name: name)
    }
}

@available(macOS 26, *)
@Generable
struct SetBackgroundMirror: MediatorCommandMirroring {
    var spec: BackgroundSpecMirror

    func toCommand() throws -> MediatorCommand {
        .setBackground(spec: try spec.toBackgroundSpec())
    }
}

@available(macOS 26, *)
@Generable
struct RenameCardMirror: MediatorCommandMirroring {
    var target: String
    var newName: String

    func toCommand() throws -> MediatorCommand {
        .renameCard(target: target, newName: newName)
    }
}

@available(macOS 26, *)
@Generable
struct DeleteCardMirror: MediatorCommandMirroring {
    var target: String

    func toCommand() throws -> MediatorCommand {
        .deleteCard(target: target)
    }
}

@available(macOS 26, *)
@Generable
struct EditNoteMirror: MediatorCommandMirroring {
    var target: String
    var content: String
    var append: Bool

    func toCommand() throws -> MediatorCommand {
        .editNote(target: target, content: content, append: append)
    }
}

@available(macOS 26, *)
@Generable
struct AddTodoItemMirror: MediatorCommandMirroring {
    var target: String
    var text: String

    func toCommand() throws -> MediatorCommand {
        .addTodoItem(target: target, text: text)
    }
}

@available(macOS 26, *)
@Generable
struct SetTodoItemDoneMirror: MediatorCommandMirroring {
    var target: String
    var text: String
    var done: Bool

    func toCommand() throws -> MediatorCommand {
        .setTodoItemDone(target: target, text: text, done: done)
    }
}

@available(macOS 26, *)
@Generable
struct DelegateMirror: MediatorCommandMirroring {
    var question: String
    var target: String?

    func toCommand() throws -> MediatorCommand {
        .delegate(question: question, target: target)
    }
}

// MARK: - Top-level guided-generation container (one wire case active)

@available(macOS 26, *)
@Generable
struct MediatorCommandMirror {
    var spawnAgents: SpawnAgentsMirror?
    var sendPrompt: SendPromptMirror?
    var readOutput: ReadOutputMirror?
    var closeTerminal: CloseTerminalMirror?
    var arrange: ArrangeMirror?
    var createCard: CreateCardMirror?
    var switchSpace: SwitchSpaceMirror?
    var setBackground: SetBackgroundMirror?
    var renameCard: RenameCardMirror?
    var deleteCard: DeleteCardMirror?
    var editNote: EditNoteMirror?
    var addTodoItem: AddTodoItemMirror?
    var setTodoItemDone: SetTodoItemDoneMirror?
    var delegate: DelegateMirror?

    func toCommand() throws -> MediatorCommand {
        let mirrors: [(any MediatorCommandMirroring)?] = [
            spawnAgents, sendPrompt, readOutput, closeTerminal,
            arrange, createCard, switchSpace, setBackground,
            renameCard, deleteCard, editNote, addTodoItem, setTodoItemDone,
            delegate,
        ]
        let selected = mirrors.compactMap { $0 }
        guard selected.count == 1, let mirror = selected.first else {
            throw MirrorConversionError.ambiguousOrEmptyCommand
        }
        return try mirror.toCommand()
    }
}

// MARK: - Conversions

@available(macOS 26, *)
enum MirrorConversionError: Error {
    case invalidAgentKind(String)
    case invalidCardKind(String)
    case ambiguousOrEmptyCommand
    case unsupportedArrangeStyle
    case unsupportedBackgroundSpec
}

@available(macOS 26, *)
extension ArrangeStyleMirror {
    fileprivate func toArrangeStyle() throws -> ArrangeStyle {
        if grid != nil { return .grid }
        if retile != nil { return .retile }
        if let focus { return .focus(target: focus.target) }
        throw MirrorConversionError.unsupportedArrangeStyle
    }
}

@available(macOS 26, *)
extension BackgroundSpecMirror {
    fileprivate func toBackgroundSpec() throws -> MediatorBackgroundSpec {
        if atmosphere != nil { return .atmosphere }
        if let solid { return .solid(hex: solid.hex) }
        throw MirrorConversionError.unsupportedBackgroundSpec
    }
}
