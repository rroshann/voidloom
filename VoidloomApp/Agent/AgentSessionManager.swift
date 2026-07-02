import AppKit
import Combine
import SwiftTerm

/// Owns one live PTY-backed shell per agent card. The manager (not the SwiftUI
/// view tree) retains each `LocalProcessTerminalView`, so terminal state —
/// scrollback, running process, cwd — survives card re-renders, Canvas/Spaces
/// mode switches, and Spaces paging. Views mount the terminal via
/// `TerminalHostView` and never talk to the process directly.
@MainActor
final class AgentSessionManager: NSObject, ObservableObject {
    final class Session {
        let terminal: LocalProcessTerminalView
        fileprivate(set) var isRunning = true

        fileprivate init(terminal: LocalProcessTerminalView) {
            self.terminal = terminal
        }
    }

    @Published private(set) var sessions: [UUID: Session] = [:]

    func startSession(cardID: UUID, workingDirectory: String? = nil) {
        guard sessions[cardID] == nil else { return }

        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        terminal.processDelegate = self
        terminal.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminal.nativeBackgroundColor = NSColor(srgbRed: 0.04, green: 0.05, blue: 0.08, alpha: 1)
        terminal.nativeForegroundColor = NSColor(srgbRed: 0.88, green: 0.91, blue: 0.94, alpha: 1)

        // Login shell (the user's own), spawned from the workspace folder when
        // set, else home — so PATH, rc files, and CLIs match Terminal.app.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let dir: String
        if let wd = workingDirectory, !wd.isEmpty, fm.fileExists(atPath: wd, isDirectory: &isDir), isDir.boolValue {
            dir = wd
        } else {
            dir = NSHomeDirectory()
        }
        fm.changeCurrentDirectoryPath(dir)
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        environment.append("SHELL=\(shell)")
        terminal.startProcess(executable: shell, args: ["-l"], environment: environment)

        sessions[cardID] = Session(terminal: terminal)
    }

    /// Kills the shell (SIGHUP, the "terminal window closed" signal) and drops
    /// the session. Card close/delete and app termination all route here.
    func terminateSession(cardID: UUID) {
        guard let session = sessions.removeValue(forKey: cardID) else { return }
        session.terminal.processDelegate = nil
        let pid = session.terminal.process.shellPid
        if pid > 0 { kill(pid, SIGHUP) }
    }

    func terminateAllSessions() {
        for cardID in Array(sessions.keys) {
            terminateSession(cardID: cardID)
        }
    }

    /// Tears down a dead (or stuck) session and spawns a fresh shell in place.
    func restartSession(cardID: UUID, workingDirectory: String? = nil) {
        terminateSession(cardID: cardID)
        startSession(cardID: cardID, workingDirectory: workingDirectory)
    }

    func session(for cardID: UUID) -> Session? {
        sessions[cardID]
    }

    private func markTerminated(_ source: TerminalView) {
        guard let entry = sessions.first(where: { $0.value.terminal === source }) else { return }
        entry.value.isRunning = false
        objectWillChange.send()
    }
}

extension AgentSessionManager: LocalProcessTerminalViewDelegate {
    // SwiftTerm invokes these on the main thread; the protocol just isn't
    // annotated, hence the assumeIsolated hop.
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            markTerminated(source)
        }
    }
}
