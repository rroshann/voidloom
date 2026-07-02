import XCTest
@testable import VoidloomCore

private final class ScriptedBrain: MediatorBrain, @unchecked Sendable {
    let result: Result<MediatorCommand, Error>
    private(set) var calls = 0
    init(_ r: Result<MediatorCommand, Error>) { result = r }
    func command(for utterance: String) async throws -> MediatorCommand { calls += 1; return try result.get() }
}

final class TieredBrainTests: XCTestCase {
    func testFastPathResultShortCircuitsFallback() async throws {
        let fast = ScriptedBrain(.success(.readOutput(target: "ember")))
        let fallback = ScriptedBrain(.success(.closeTerminal(target: "x")))
        let cmd = try await TieredBrain(fast: fast, fallback: fallback).command(for: "show ember")
        XCTAssertEqual(cmd, .readOutput(target: "ember"))
        XCTAssertEqual(fallback.calls, 0)
    }

    func testUnparseableFallsThroughToLLM() async throws {
        let fast = ScriptedBrain(.failure(BrainError.unparseable("huh")))
        let fallback = ScriptedBrain(.success(.switchSpace(name: "research")))
        let cmd = try await TieredBrain(fast: fast, fallback: fallback).command(for: "take me to research please")
        XCTAssertEqual(cmd, .switchSpace(name: "research"))
        XCTAssertEqual(fallback.calls, 1)
    }

    func testNonUnparseableFastErrorDoesNotFallThrough() async {
        let fast = ScriptedBrain(.failure(BrainError.backendFailure("io")))
        let fallback = ScriptedBrain(.success(.readOutput(target: "x")))
        let brain = TieredBrain(fast: fast, fallback: fallback)
        do { _ = try await brain.command(for: "x"); XCTFail() }
        catch let e as BrainError { if case .backendFailure = e {} else { XCTFail() } }
        catch { XCTFail() }
    }
}
