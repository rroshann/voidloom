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

    func testManifestPinsTheChatModelVerifiedAgainstHuggingFace() {
        let m = LocalModelManifest.chatModel
        XCTAssertEqual(m.sha256, "b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897")
        XCTAssertEqual(m.sizeBytes, 1_107_409_472)
        XCTAssertEqual(m.license, "Apache-2.0")
    }

    // MARK: coalescing + cancel (via a stalling URLProtocol — no real network)

    private func stallingManager() -> (ModelAssetManager, LocalModelAsset) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StallingURLProtocol.self]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let mgr = ModelAssetManager(modelsDirectory: root, sessionConfiguration: config)
        let asset = LocalModelAsset(
            id: "stall", filename: "stall.gguf", url: URL(string: "stall://model/x")!,
            sha256: String(repeating: "0", count: 64), sizeBytes: 1,
            license: "Apache-2.0", displayName: "Stall")
        return (mgr, asset)
    }

    private func poll(timeout: TimeInterval = 3, until cond: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() {
            if Date() > deadline { XCTFail("poll timed out"); return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testConcurrentDownloadsCoalesceIntoASingleTask() async throws {
        let (mgr, asset) = stallingManager()
        async let a: Void = { try? await mgr.download(asset) }()
        async let b: Void = { try? await mgr.download(asset) }()
        try await poll { mgr.downloadTaskCreationCount == 1 }
        mgr.cancel(asset)
        _ = await (a, b)
        XCTAssertEqual(mgr.downloadTaskCreationCount, 1)
    }

    func testCancelMidDownloadResolvesToMissingNotFailed() async throws {
        let (mgr, asset) = stallingManager()
        let dl = Task { try await mgr.download(asset) }
        try await poll { mgr.downloadTaskCreationCount == 1 }
        mgr.cancel(asset)
        do { try await dl.value; XCTFail("expected cancellation to throw") } catch {}
        XCTAssertEqual(mgr.state(of: asset), .missing)
        XCTAssertNil(mgr.localURL(of: asset))
    }
}

/// Intercepts `stall://` requests and never delivers data, so a download stays
/// in flight until the task is cancelled — deterministic, and never touches the
/// network.
final class StallingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "stall"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { /* intentionally never completes */ }
    override func stopLoading() { /* nothing to tear down */ }
}
