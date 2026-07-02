import XCTest
import CryptoKit
@testable import VoidloomAI

@MainActor
final class ModelAssetManagerTests: XCTestCase {
    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Serves a fixture file over file:// and returns a matching asset.
    private func fixtureAsset(bytes: Data, id: String = "fixture") throws -> (LocalModelAsset, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("\(id).bin")
        try bytes.write(to: src)
        let asset = LocalModelAsset(
            id: id, filename: "\(id).gguf", url: src,
            sha256: sha256Hex(bytes), sizeBytes: Int64(bytes.count),
            license: "Apache-2.0", displayName: "Fixture")
        return (asset, dir)
    }

    private func makeManager() -> (ModelAssetManager, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (ModelAssetManager(modelsDirectory: root), root)
    }

    func testMissingUntilDownloadedThenReady() async throws {
        let (asset, _) = try fixtureAsset(bytes: Data((0..<4096).map { UInt8($0 & 0xFF) }))
        let (mgr, root) = makeManager()
        XCTAssertEqual(mgr.state(of: asset), .missing)
        try await mgr.download(asset)
        XCTAssertEqual(mgr.state(of: asset), .ready)
        let dest = root.appendingPathComponent(asset.filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertEqual(mgr.localURL(of: asset), dest)
    }

    func testChecksumMismatchFailsAndDoesNotMarkReady() async throws {
        var (asset, _) = try fixtureAsset(bytes: Data([1, 2, 3, 4]))
        asset = LocalModelAsset(id: asset.id, filename: asset.filename, url: asset.url,
                                sha256: String(repeating: "0", count: 64), sizeBytes: asset.sizeBytes,
                                license: asset.license, displayName: asset.displayName)
        let (mgr, _) = makeManager()
        do { try await mgr.download(asset); XCTFail("expected checksum failure") }
        catch { }
        if case .failed = mgr.state(of: asset) {} else { XCTFail("expected .failed, got \(mgr.state(of: asset))") }
    }

    func testVerifyExistingRecognizesAPreviouslyDownloadedFile() async throws {
        let bytes = Data((0..<8192).map { UInt8($0 & 0xFF) })
        let (asset, _) = try fixtureAsset(bytes: bytes)
        let (mgr, root) = makeManager()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try bytes.write(to: root.appendingPathComponent(asset.filename))
        let verified = await mgr.verifyExisting(asset)
        XCTAssertTrue(verified)
        XCTAssertEqual(mgr.state(of: asset), .ready)
    }

    func testManifestPinsTheCommandModelFromTheSpike() {
        let m = LocalModelManifest.commandModel
        XCTAssertEqual(m.sha256, "ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a")
        XCTAssertEqual(m.sizeBytes, 396_705_472)
        XCTAssertEqual(m.license, "Apache-2.0")
    }
}
