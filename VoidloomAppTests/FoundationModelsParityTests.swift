import XCTest
import FoundationModels
import VoidloomCore
@testable import Voidloom

final class FoundationModelsParityTests: XCTestCase {
    // MARK: - Pure parity (no live FM required)

    func testMirrorRegistryMatchesFrozenSchemaCases() {
        guard #available(macOS 26, *) else { return }
        XCTAssertEqual(
            Set(MediatorToolMirrors.mirrorCaseNames),
            Set(MediatorCommandSchema.cases.map(\.name))
        )
        XCTAssertEqual(
            MediatorToolMirrors.mirrorCaseNames.count,
            MediatorCommandSchema.cases.count,
            "duplicate mirror case name"
        )
    }

    func testEachMirrorToCommandMatchesFrozenCodableSamples() throws {
        guard #available(macOS 26, *) else { return }
        for schemaCase in MediatorCommandSchema.cases {
            let name = schemaCase.name
            let json = try XCTUnwrap(MediatorCommandSchema.samples[name], "missing sample for \(name)")
            let expected = try JSONDecoder().decode(
                MediatorCommand.self,
                from: Data(json.utf8))
            let mirror = try XCTUnwrap(
                MediatorToolMirrors.sampleMirror(named: name),
                "missing sample mirror for \(name)")
            let command = try mirror.toCommand()
            XCTAssertEqual(command, expected, name)

            let reencoded = try JSONEncoder().encode(command)
            let top = try XCTUnwrap(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
            XCTAssertEqual(top.keys.first, name, "wire top-level key drifted for \(name)")
        }
    }

    // MARK: - Live guided generation (FM + macOS 26 required)

    func testLiveGuidedGenerationSwitchToResearch() async throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Requires macOS 26")
        }
        try requireFoundationModelsOrSkip()

        let brain = FoundationModelsBrain()
        let command = try await brain.command(for: "switch to research")
        XCTAssertEqual(command, .switchSpace(name: "research"))
    }

    @available(macOS 26, *)
    private func requireFoundationModelsOrSkip() throws {
        switch SystemLanguageModel.default.availability {
        case .available:
            return
        case .unavailable(let reason):
            throw XCTSkip("Foundation Models unavailable: \(reason)")
        }
    }
}
