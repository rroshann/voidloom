import Foundation

enum AgentCommandError: Error, Equatable {
    case commandNotFound
    case timedOut
    case failed(String)
}

/// Runs a one-shot shell command for delegation and returns its stdout. A
/// protocol so `DelegationService` is unit-testable against a fake; the real
/// implementation shells out via a login shell so the agent CLI resolves on PATH.
protocol AgentCommandRunning: Sendable {
    func run(_ command: String, in directory: String?, timeout: TimeInterval) async throws -> String
}

/// Runs the command through `/bin/zsh -lc` (login shell → user's real PATH, so
/// `claude`/`codex` resolve), captures stdout, and terminates the subprocess if
/// it exceeds the timeout so a hung CLI can't leak.
struct ProcessAgentCommandRunner: AgentCommandRunning {
    func run(_ command: String, in directory: String?, timeout: TimeInterval) async throws -> String {
        let box = ProcessBox()
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try box.runToCompletion(command, in: directory) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                box.terminate()
                throw AgentCommandError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw AgentCommandError.failed("no result")
            }
            return result
        }
    }
}

/// Holds the Process so the timeout task can terminate it. Runs the subprocess
/// synchronously on a background thread (via the task group's executor).
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func terminate() {
        lock.lock(); let p = process; lock.unlock()
        if p?.isRunning == true { p?.terminate() }
    }

    func runToCompletion(_ command: String, in directory: String?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        if let directory, FileManager.default.fileExists(atPath: directory) {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        lock.lock(); self.process = process; lock.unlock()
        do {
            try process.run()
        } catch {
            throw AgentCommandError.commandNotFound
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(data: outData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // 127 = command not found from the shell.
            if process.terminationStatus == 127 || err.lowercased().contains("command not found") {
                throw AgentCommandError.commandNotFound
            }
            throw AgentCommandError.failed(err.isEmpty ? "exit \(process.terminationStatus)" : err)
        }
        return out
    }
}
