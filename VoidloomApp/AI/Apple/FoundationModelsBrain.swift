import Foundation
import FoundationModels
import VoidloomCore

/// Tier-1 Apple Intelligence brain. Guided generation produces a
/// `MediatorCommandMirror`, converted to `MediatorCommand` for execution.
@available(macOS 26, *)
final class FoundationModelsBrain: MediatorBrain, @unchecked Sendable {
    private let session: LanguageModelSession

    init(systemPrompt: String = FoundationModelsBrain.defaultSystemPrompt) {
        self.session = LanguageModelSession(instructions: systemPrompt)
        if case .available = SystemLanguageModel.default.availability {
            session.prewarm()
        }
    }

    func command(for utterance: String) async throws -> MediatorCommand {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw BrainError.modelNotReady(Self.unavailableMessage(reason))
        }

        do {
            let response = try await session.respond(
                to: utterance,
                generating: MediatorCommandMirror.self)
            return try response.content.toCommand()
        } catch is MirrorConversionError {
            throw BrainError.unparseable(utterance)
        } catch {
            throw Self.mapGenerationError(error, utterance: utterance)
        }
    }

    static let defaultSystemPrompt = """
    You translate ONE spoken workspace command into a structured command. Fill EXACTLY ONE \
    of the command fields — the single best match — and leave every other field null. Never \
    fill spawnAgents unless the user clearly asks to create or start agents. \
    Examples:
    ask ember to fix the build -> sendPrompt(target: ember, text: fix the build)
    start 4 claude agents -> spawnAgents(count: 4, kind: claude)
    switch to research -> switchSpace(name: research)
    go to the design space -> switchSpace(name: design)
    close ember -> closeTerminal(target: ember)
    read what slate is saying -> readOutput(target: slate)
    tile the windows in a grid -> arrange(grid)
    make a todo that says buy milk -> createCard(kind: todo, content: buy milk)
    rename ember to scout -> renameCard(target: ember, newName: scout)
    ask ember about how persistence works -> delegate(question: how persistence works, target: ember)
    relay ember to slate -> relayBetweenAgents(from: ember, to: slate)
    brief ember -> briefAgent(target: ember)
    """

    private static func unavailableMessage(
        _ reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This Mac isn't eligible for Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in System Settings."
        case .modelNotReady:
            return "Apple Intelligence is still downloading — try again shortly."
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    private static func mapGenerationError(_ error: Error, utterance: String) -> BrainError {
        if isGuardrailOrRefusal(error) {
            return .unparseable(utterance)
        }
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return .backendFailure(localized)
        }
        return .backendFailure("Apple Intelligence failed to respond.")
    }

    private static func isGuardrailOrRefusal(_ error: Error) -> Bool {
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .guardrailViolation, .refusal:
                return true
            default:
                return false
            }
        }
        // LanguageModelError exists only in the macOS 27 SDK (Xcode 27 / Swift 6.4+);
        // the compiler gate keeps Xcode 26 toolchains (CI) building, the #available
        // keeps the binary safe on older macOS at runtime.
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            if let model = error as? LanguageModelError {
                switch model {
                case .guardrailViolation, .refusal:
                    return true
                default:
                    return false
                }
            }
        }
        #endif
        return false
    }
}
