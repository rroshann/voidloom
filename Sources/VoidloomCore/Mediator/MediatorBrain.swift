import Foundation

/// Text in, one validated command out. Implementations are schema-constrained
/// (FoundationModels tools / GBNF) so anything else is structurally impossible;
/// unparseable utterances throw and surface as `parseFailed`.
public protocol MediatorBrain: AnyObject, Sendable {
    func command(for utterance: String) async throws -> MediatorCommand
}
