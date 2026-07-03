import Foundation
import SwiftUI
import VoidloomCore

/// Shows the working-tree changes of the space's git repo: a list of modified
/// files (with status + path) and the +/- diff of the selected one. If the space
/// has no folder, offers a picker; if the folder isn't a repo, says so.
struct GitCardContentView: View {
    @ObservedObject var store: WorkspaceStore
    let accent: Color

    @State private var branch = ""
    @State private var changes: [GitChange] = []
    @State private var selected: GitChange.ID?
    @State private var diffLines: [DiffLine] = []
    @State private var status: LoadStatus = .idle

    private enum LoadStatus: Equatable { case idle, loading, notARepo, error(String), ok }

    private var folderPath: String? { store.state.space?.folderPath }

    var body: some View {
        Group {
            if let folderPath, !folderPath.isEmpty {
                repoView(URL(fileURLWithPath: folderPath))
            } else {
                CardFolderMissing(message: "No project folder is set for this workspace.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: folderPath) { await reload() }
    }

    @ViewBuilder
    private func repoView(_ root: URL) -> some View {
        VStack(spacing: 0) {
            header(root)
            Divider().overlay(.white.opacity(0.08))

            switch status {
            case .notARepo:
                message("This workspace isn't a git repository — git tracking and diff are unavailable.", icon: "xmark.seal")
            case .error(let e):
                message(e, icon: "exclamationmark.triangle")
            case .ok where changes.isEmpty:
                message("No changes — working tree clean.", icon: "checkmark.seal")
            default:
                VStack(spacing: 0) {
                    changeList
                    Divider().overlay(.white.opacity(0.08))
                    diffPane
                }
            }
        }
    }

    private func header(_ root: URL) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(root.lastPathComponent)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                .lineLimit(1).truncationMode(.middle)
            if !branch.isEmpty {
                Text(branch)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(accent.opacity(0.16)))
            }
            Spacer(minLength: 4)
            Button { Task { await reload() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6)).help("Refresh")
            .accessibilityLabel("Refresh")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    private var changeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(changes) { change in
                    HStack(spacing: 8) {
                        Text(change.badge)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(change.badgeColor)
                            .frame(width: 18, alignment: .leading)
                        Text(change.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected == change.id ? accent.opacity(0.18) : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { select(change) }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 120)
    }

    private var diffPane: some View {
        ScrollView([.vertical, .horizontal]) {
            if diffLines.isEmpty {
                Text(selected == nil ? "Select a file to see its diff." : "No textual diff.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    .padding(12)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(diffLines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(line.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func message(_ text: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26, weight: .light)).foregroundStyle(.white.opacity(0.4))
                .accessibilityHidden(true)
            Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private func select(_ change: GitChange) {
        selected = change.id
        Task {
            let dir = URL(fileURLWithPath: folderPath ?? "")
            let args = change.isUntracked
                ? ["diff", "--no-index", "--", "/dev/null", change.path]
                : ["diff", "HEAD", "--", change.path]
            let result = await Git.run(args, in: dir)
            diffLines = DiffLine.parse(result.out)
        }
    }

    private func reload() async {
        guard let folderPath, !folderPath.isEmpty else { return }
        let dir = URL(fileURLWithPath: folderPath)
        status = .loading
        let statusResult = await Git.run(["status", "--porcelain"], in: dir)
        if statusResult.code != 0 {
            let msg = statusResult.err.lowercased()
            status = msg.contains("not a git repository") ? .notARepo : .error(statusResult.err.trimmingCharacters(in: .whitespacesAndNewlines))
            changes = []; diffLines = []; branch = ""
            return
        }
        branch = (await Git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: dir))
            .out.trimmingCharacters(in: .whitespacesAndNewlines)
        changes = GitChange.parse(statusResult.out)
        status = .ok
        // Keep a valid selection; refresh its diff or clear.
        if let sel = selected, let change = changes.first(where: { $0.id == sel }) {
            select(change)
        } else {
            selected = nil; diffLines = []
        }
    }

}

/// One entry from `git status --porcelain`.
struct GitChange: Identifiable, Equatable {
    // Stable id (the path) so the selected file survives a reload/refresh —
    // git status lists each path once.
    var id: String { path }
    let code: String    // two-char XY status
    let path: String

    var isUntracked: Bool { code == "??" }
    var badge: String { code.trimmingCharacters(in: .whitespaces).isEmpty ? "•" : code.trimmingCharacters(in: .whitespaces) }

    var badgeColor: Color {
        if isUntracked { return Color(red: 0.6, green: 0.6, blue: 0.6) }
        if code.contains("A") { return Color(red: 0.5, green: 0.85, blue: 0.5) }
        if code.contains("D") { return Color(red: 0.95, green: 0.5, blue: 0.5) }
        return Color(red: 0.95, green: 0.75, blue: 0.4)   // modified
    }

    static func parse(_ porcelain: String) -> [GitChange] {
        porcelain.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let s = String(line)
            guard s.count > 3 else { return nil }
            let code = String(s.prefix(2))
            var path = String(s.dropFirst(3))
            // Renames render as "orig -> new"; show the new path.
            if let arrow = path.range(of: " -> ") { path = String(path[arrow.upperBound...]) }
            return GitChange(code: code, path: path)
        }
    }
}

/// A single colored diff line.
struct DiffLine: Identifiable {
    let id = UUID()
    let text: String
    let color: Color

    static func parse(_ diff: String) -> [DiffLine] {
        diff.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let s = String(raw)
            let color: Color
            if s.hasPrefix("+") && !s.hasPrefix("+++") { color = Color(red: 0.55, green: 0.87, blue: 0.55) }
            else if s.hasPrefix("-") && !s.hasPrefix("---") { color = Color(red: 0.95, green: 0.52, blue: 0.52) }
            else if s.hasPrefix("@@") { color = Color(red: 0.5, green: 0.78, blue: 1.0) }
            else if s.hasPrefix("diff ") || s.hasPrefix("index ") || s.hasPrefix("+++") || s.hasPrefix("---") {
                color = .white.opacity(0.45)
            } else { color = .white.opacity(0.8) }
            return DiffLine(text: s, color: color)
        }
    }
}

/// Minimal async `git` runner. Runs off the main thread and returns stdout,
/// stderr, and the exit code. The app is un-sandboxed, so it can spawn git.
enum Git {
    static func run(_ args: [String], in directory: URL) async -> (out: String, err: String, code: Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                // Pin to the standard git path — a GUI app's PATH is minimal, so
                // `/usr/bin/env git` can fail to resolve. Fall back to env lookup
                // if the CLT shim isn't there.
                if FileManager.default.isExecutableFile(atPath: "/usr/bin/git") {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                    process.arguments = args
                } else {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = ["git"] + args
                }
                process.currentDirectoryURL = directory
                let outPipe = Pipe(), errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ("", error.localizedDescription, -1))
                    return
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (
                    String(decoding: outData, as: UTF8.self),
                    String(decoding: errData, as: UTF8.self),
                    process.terminationStatus
                ))
            }
        }
    }
}
