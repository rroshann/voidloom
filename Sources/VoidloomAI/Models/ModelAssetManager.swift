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

    /// `nonisolated` so the download delegate can stage on the same volume as the
    /// destination (an atomic rename requires both paths share a volume).
    nonisolated let modelsDirectory: URL
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var inFlight: [String: Task<Void, Error>] = [:]
    private let sessionConfiguration: URLSessionConfiguration
    private lazy var session: URLSession = {
        URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }()

    /// Test seam: counts how many URLSession download tasks have been created, so
    /// coalescing can be proven (two `download` calls for one asset ⇒ one task).
    private(set) var downloadTaskCreationCount = 0

    public init(modelsDirectory: URL = ModelAssetManager.defaultModelsDirectory(),
                sessionConfiguration: URLSessionConfiguration = .default) {
        self.modelsDirectory = modelsDirectory
        self.sessionConfiguration = sessionConfiguration
        super.init()
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        Self.sweepStalePartials(in: modelsDirectory)
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

    /// Downloads (or awaits an in-flight download of) the asset. Concurrent calls
    /// for the same asset coalesce onto a single download task; the second caller
    /// awaits the first's result rather than spawning a duplicate.
    public func download(_ asset: LocalModelAsset) async throws {
        if let existing = inFlight[asset.id] {
            try await existing.value
            return
        }
        let work = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.performDownload(asset)
        }
        inFlight[asset.id] = work
        defer { inFlight[asset.id] = nil }
        try await work.value
    }

    private func performDownload(_ asset: LocalModelAsset) async throws {
        let dest = destinationURL(of: asset)
        if FileManager.default.fileExists(atPath: dest.path),
           await Self.checksumMatches(fileURL: dest, expected: asset.sha256) {
            states[asset.id] = .ready; return
        }
        states[asset.id] = .downloading(progress: 0)
        let staged: URL
        do {
            staged = try await runDownload(asset)
        } catch {
            cleanupTaskState(assetID: asset.id)
            if Self.isCancellation(error) {
                // A user cancel is not a failure: return to the on-disk truth.
                states[asset.id] = diskState(of: asset)
            } else {
                states[asset.id] = .failed(reason: error.localizedDescription)
            }
            throw error
        }
        cleanupTaskState(assetID: asset.id)
        states[asset.id] = .verifying
        guard await Self.checksumMatches(fileURL: staged, expected: asset.sha256) else {
            try? FileManager.default.removeItem(at: staged)
            states[asset.id] = .failed(reason: "Downloaded file failed integrity check.")
            throw ModelAssetError.checksumMismatch(assetID: asset.id)
        }
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: staged, to: dest)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            states[asset.id] = .failed(reason: error.localizedDescription)
            throw error
        }
        states[asset.id] = .ready
    }

    public func cancel(_ asset: LocalModelAsset) {
        if let task = tasks[asset.id] {
            // Cancelling surfaces as a cancellation error in performDownload,
            // which finalizes state — avoiding a race with this synchronous set.
            task.cancel()
        } else {
            states[asset.id] = diskState(of: asset)
        }
    }

    // MARK: download plumbing

    private var continuations: [Int: CheckedContinuation<URL, Error>] = [:]
    private var progressAsset: [Int: String] = [:]

    private func runDownload(_ asset: LocalModelAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: asset.url)
            downloadTaskCreationCount += 1
            tasks[asset.id] = task
            continuations[task.taskIdentifier] = continuation
            progressAsset[task.taskIdentifier] = asset.id
            task.resume()
        }
    }

    private func cleanupTaskState(assetID: String) {
        tasks[assetID] = nil
        progressAsset = progressAsset.filter { $0.value != assetID }
    }

    private func diskState(of asset: LocalModelAsset) -> ModelAssetState {
        FileManager.default.fileExists(atPath: destinationURL(of: asset).path) ? .ready : .missing
    }

    fileprivate func finishDownload(taskID: Int, movedTo staged: URL?, error: Error?) {
        guard let continuation = continuations.removeValue(forKey: taskID) else {
            // Continuation already resolved (e.g. cancel raced completion); the
            // staged file, if any, would be orphaned — remove it.
            if let staged { try? FileManager.default.removeItem(at: staged) }
            return
        }
        if let error { continuation.resume(throwing: error) }
        else if let staged { continuation.resume(returning: staged) }
        else { continuation.resume(throwing: ModelAssetError.downloadProducedNoFile) }
    }

    fileprivate func report(taskID: Int, progress: Double) {
        guard let id = progressAsset[taskID] else { return }
        states[id] = .downloading(progress: progress)
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    private static func sweepStalePartials(in directory: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.pathExtension == "partial" {
            try? FileManager.default.removeItem(at: url)
        }
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
        // Stage synchronously (the temp file is deleted on return) INSIDE the
        // models directory, so the later rename to the destination is atomic
        // (same volume by construction).
        let staged = modelsDirectory.appendingPathComponent("\(UUID().uuidString).partial")
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
