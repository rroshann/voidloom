import Foundation

/// One downloadable model asset with its pinned integrity + license data.
public struct LocalModelAsset: Identifiable, Equatable, Sendable {
    public let id: String
    public let filename: String
    public let url: URL
    public let sha256: String
    public let sizeBytes: Int64
    public let license: String
    public let displayName: String

    public init(id: String, filename: String, url: URL, sha256: String,
                sizeBytes: Int64, license: String, displayName: String) {
        self.id = id; self.filename = filename; self.url = url
        self.sha256 = sha256; self.sizeBytes = sizeBytes
        self.license = license; self.displayName = displayName
    }
}

/// The pinned, revision-locked asset manifest. URLs use Hugging Face
/// `resolve/<revision>/<file>` so the bytes cannot change under us; SHA256 is
/// verified after download. Command model values are from the spike
/// (`.omc/research/spike-llama.md`); the chat model is pinned in Task 8.
public enum LocalModelManifest {
    public static let commandModel = LocalModelAsset(
        id: "qwen3-0.6b-q4km",
        filename: "Qwen3-0.6B-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/50968a4468ef4233ed78cd7c3de230dd1d61a56b/Qwen3-0.6B-Q4_K_M.gguf")!,
        sha256: "ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a",
        sizeBytes: 396_705_472,
        license: "Apache-2.0",
        displayName: "Qwen3 0.6B (command parser)")

    // Chat model is defined in Task 8 as `LocalModelManifest.chatModel`.
}
