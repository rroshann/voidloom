import Combine
import CryptoKit
import Foundation

public enum ModelAssetState: Equatable, Sendable {
    case missing
    case downloading(progress: Double)
    case verifying
    case ready
    case failed(reason: String)
}

/// Downloads model assets on first use into Application Support/Voidloom/Models,
/// verifies SHA256, and publishes per-asset state. Resumable via URLSession
/// download tasks. Pure Foundation + CryptoKit — no llama, no SwiftUI — so it
/// is headlessly testable against a file:// fixture.
@MainActor
public final class ModelAssetManager: NSObject, ObservableObject {
    @Published private var states: [String: ModelAssetState] = [:]

    private let modelsDirectory: URL
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    public init(modelsDirectory: URL = ModelAssetManager.defaultModelsDirectory()) {
        self.modelsDirectory = modelsDirectory
        super.init()
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    public static func defaultModelsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Voidloom/Models", isDirectory: true)
    }

    public func destinationURL(of asset: LocalModelAsset) -> URL {
        modelsDirectory.appendingPathComponent(asset.filename)
    }

    public func localURL(of asset: LocalModelAsset) -> URL? {
        let url = destinationURL(of: asset)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func state(of asset: LocalModelAsset) -> ModelAssetState {
        if let s = states[asset.id] { return s }
        return FileManager.default.fileExists(atPath: destinationURL(of: asset).path) ? .ready : .missing
    }

    /// Confirms an on-disk file matches the pinned checksum; flips to .ready or .missing.
    public func verifyExisting(_ asset: LocalModelAsset) async -> Bool {
        let dest = destinationURL(of: asset)
        guard FileManager.default.fileExists(atPath: dest.path) else {
            states[asset.id] = .missing; return false
        }
        states[asset.id] = .verifying
        let ok = await Self.checksumMatches(fileURL: dest, expected: asset.sha256)
        states[asset.id] = ok ? .ready : .missing
        if !ok { try? FileManager.default.removeItem(at: dest) }
        return ok
    }

    public func download(_ asset: LocalModelAsset) async throws {
        let dest = destinationURL(of: asset)
        if FileManager.default.fileExists(atPath: dest.path),
           await Self.checksumMatches(fileURL: dest, expected: asset.sha256) {
            states[asset.id] = .ready; return
        }
        states[asset.id] = .downloading(progress: 0)
        let tempURL: URL
        do {
            tempURL = try await runDownload(asset)
        } catch {
            states[asset.id] = .failed(reason: error.localizedDescription); throw error
        }
        states[asset.id] = .verifying
        guard await Self.checksumMatches(fileURL: tempURL, expected: asset.sha256) else {
            try? FileManager.default.removeItem(at: tempURL)
            let reason = "Downloaded file failed integrity check."
            states[asset.id] = .failed(reason: reason)
            throw ModelAssetError.checksumMismatch(assetID: asset.id)
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        states[asset.id] = .ready
    }

    public func cancel(_ asset: LocalModelAsset) {
        tasks[asset.id]?.cancel(); tasks[asset.id] = nil
        states[asset.id] = FileManager.default.fileExists(atPath: destinationURL(of: asset).path) ? .ready : .missing
    }

    // MARK: download plumbing

    private var continuations: [Int: CheckedContinuation<URL, Error>] = [:]

    private func runDownload(_ asset: LocalModelAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: asset.url)
            tasks[asset.id] = task
            continuations[task.taskIdentifier] = continuation
            progressAsset[task.taskIdentifier] = asset.id
            task.resume()
        }
    }

    private var progressAsset: [Int: String] = [:]

    fileprivate func finishDownload(taskID: Int, movedTo staged: URL?, error: Error?) {
        guard let continuation = continuations.removeValue(forKey: taskID) else { return }
        if let error { continuation.resume(throwing: error) }
        else if let staged { continuation.resume(returning: staged) }
        else { continuation.resume(throwing: ModelAssetError.downloadProducedNoFile) }
    }

    fileprivate func report(taskID: Int, progress: Double) {
        guard let id = progressAsset[taskID] else { return }
        states[id] = .downloading(progress: progress)
    }

    static func checksumMatches(fileURL: URL, expected: String) async -> Bool {
        await Task.detached(priority: .utility) {
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return hex.caseInsensitiveCompare(expected) == .orderedSame
        }.value
    }
}

public enum ModelAssetError: Error, Equatable {
    case checksumMismatch(assetID: String)
    case downloadProducedNoFile
}

extension ModelAssetManager: URLSessionDownloadDelegate {
    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                       didFinishDownloadingTo location: URL) {
        // Stage synchronously in the delegate (the temp file is deleted on return).
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let moveError: Error?
        do { try FileManager.default.moveItem(at: location, to: staged); moveError = nil }
        catch { moveError = error }
        let id = downloadTask.taskIdentifier
        Task { @MainActor [weak self] in
            self?.finishDownload(taskID: id, movedTo: moveError == nil ? staged : nil, error: moveError)
        }
    }

    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                       didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                       totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let id = downloadTask.taskIdentifier
        Task { @MainActor [weak self] in self?.report(taskID: id, progress: p) }
    }

    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                       didCompleteWithError error: Error?) {
        guard let error else { return } // success handled in didFinishDownloadingTo
        let id = task.taskIdentifier
        Task { @MainActor [weak self] in self?.finishDownload(taskID: id, movedTo: nil, error: error) }
    }
}
