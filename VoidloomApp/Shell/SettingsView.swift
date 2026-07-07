import SwiftUI
import VoidloomAI
import VoidloomCore

// MARK: - Settings Root

/// macOS-native preferences window. Renders the standard preference-window
/// toolbar via `TabView` + `.tabItem`. Each tab body is its own small struct
/// wrapping a grouped `Form`. The window is fixed-width; height auto-fits the
/// tallest tab per macOS Settings conventions.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            CanvasSettingsTab()
                .tabItem { Label("Canvas", systemImage: "square.grid.3x3") }

            SpacesSettingsTab()
                .tabItem { Label("Spaces", systemImage: "rectangle.grid.2x2") }

            CardsSettingsTab()
                .tabItem { Label("Cards", systemImage: "rectangle.on.rectangle") }

            AISettingsTab()
                .tabItem { Label("AI", systemImage: "sparkles") }

            StorageSettingsTab()
                .tabItem { Label("Storage", systemImage: "internaldrive") }

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .tabViewStyle(.automatic)
        .frame(width: 580)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    enum LaunchBehavior: String, CaseIterable, Identifiable {
        case reopenLast = "Reopen last workspace"
        case emptyCanvas = "Open empty canvas"
        case picker = "Show workspace picker"
        var id: String { rawValue }
    }

    enum DefaultCard: String, CaseIterable, Identifiable {
        case note = "Note"
        case todo = "Todo"
        case agent = "Agent"
        case browser = "Browser"
        var id: String { rawValue }
    }

    enum UpdateChannel: String, CaseIterable, Identifiable {
        case stable = "Stable"
        case beta = "Beta"
        var id: String { rawValue }
    }

    // Preserved existing key.
    @AppStorage("general.launchBehavior") private var launchBehavior: LaunchBehavior = .reopenLast
    @AppStorage("general.defaultCard") private var defaultCard: DefaultCard = .note
    @AppStorage("general.confirmDelete") private var confirmDelete = true
    @AppStorage("general.showAISidebar") private var showAISidebar = true
    @AppStorage("general.rememberSidebarWidths") private var rememberSidebarWidths = true
    @AppStorage("general.autoCheckUpdates") private var autoCheckUpdates = true
    @AppStorage("general.updateChannel") private var updateChannel: UpdateChannel = .stable

    var body: some View {
        Form {
            Section("Startup") {
                Picker("On launch", selection: $launchBehavior) {
                    ForEach(LaunchBehavior.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)

                Picker("Default new card", selection: $defaultCard) {
                    ForEach(DefaultCard.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)

                Toggle("Confirm before deleting cards", isOn: $confirmDelete)
            }

            Section("Sidebars") {
                Toggle("Show AI conversation sidebar", isOn: $showAISidebar)
                Toggle("Remember sidebar widths", isOn: $rememberSidebarWidths)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $autoCheckUpdates)

                Picker("Update channel", selection: $updateChannel) {
                    ForEach(UpdateChannel.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .disabled(true)

                Text("Update channels are coming soon.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @AppStorage("appearance.mode") private var appearanceMode: AppearanceMode = .dark
    @AppStorage("appearance.accentHex") private var accentHex = "#5EE6D3"
    @AppStorage("appearance.reduceTransparency") private var reduceTransparency = false
    @AppStorage("appearance.canvasBackground") private var canvasBackground: CanvasBackground = .dots
    @AppStorage("appearance.backgroundContrast") private var backgroundContrast = 0.35
    @AppStorage("appearance.showVignette") private var showVignette = false
    @AppStorage("appearance.textSize") private var textSize: TextSize = .medium
    @AppStorage("appearance.monospacedMetadata") private var monospacedMetadata = true

    /// Curated accent presets — one tap, no fighting the system color wheel.
    private static let accentPresets = [
        "#5EE6D3", "#38C6FF", "#5B8CFF", "#A56BFF",
        "#FF6AC1", "#FF5A5F", "#FFB44A", "#7CE38B"
    ]

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)

                LabeledContent("Accent color") {
                    HStack(spacing: 8) {
                        ForEach(Self.accentPresets, id: \.self) { hex in
                            AccentSwatch(
                                hex: hex,
                                isSelected: accentHex.caseInsensitiveCompare(hex) == .orderedSame
                            ) { accentHex = hex }
                        }
                        ColorPicker("Custom accent color", selection: Binding(
                            get: { Color(hex: accentHex) },
                            set: { accentHex = $0.toHex() }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        .help("Custom…")
                    }
                }

                Toggle("Reduce transparency in panels", isOn: $reduceTransparency)
            }

            Section("Canvas") {
                Picker("Background style", selection: $canvasBackground) {
                    ForEach(CanvasBackground.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.menu)

                LabeledContent("Background contrast") {
                    Slider(value: $backgroundContrast, in: 0...1) {
                        Text("Background contrast")
                    } minimumValueLabel: {
                        Text("Faint")
                    } maximumValueLabel: {
                        Text("Bold")
                    }
                    .frame(width: 240)
                }

                Toggle("Show canvas vignette", isOn: $showVignette)
            }

            Section("Interface Text") {
                Picker("Interface text size", selection: $textSize) {
                    ForEach(TextSize.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.menu)

                Toggle("Monospaced metadata labels", isOn: $monospacedMetadata)
            }
        }
        .formStyle(.grouped)
    }
}

/// A tappable accent preset. Shows a ring when it's the active accent.
private struct AccentSwatch: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: 2)
                        .padding(-3)
                        .opacity(isSelected ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .help("Use \(hex)")
    }
}

// MARK: - Canvas

private struct CanvasSettingsTab: View {
    @AppStorage("canvas.scrollZooms") private var scrollZooms = true
    @AppStorage("canvas.invertPan") private var invertPan = false
    @AppStorage("canvas.zoomSensitivity") private var zoomSensitivity = 1.0
    @AppStorage("canvas.zoomTowardCursor") private var zoomTowardCursor = true
    @AppStorage("canvas.defaultZoom") private var defaultZoom = 100
    @AppStorage("canvas.momentumPanning") private var momentumPanning = true
    @AppStorage("canvas.selectionBoxModifier") private var selectionBoxModifier: SelectionBoxModifier = .none

    var body: some View {
        Form {
            Section("Navigation") {
                Toggle("Scroll wheel zooms", isOn: $scrollZooms)
                Toggle("Invert pan direction", isOn: $invertPan)

                LabeledContent("Zoom sensitivity") {
                    Slider(value: $zoomSensitivity, in: 0.25...3.0) {
                        Text("Zoom sensitivity")
                    } minimumValueLabel: {
                        Text("Slow")
                    } maximumValueLabel: {
                        Text("Fast")
                    }
                    .frame(width: 240)
                }

                Toggle("Zoom toward cursor", isOn: $zoomTowardCursor)

                Picker("Selection box modifier", selection: $selectionBoxModifier) {
                    ForEach(SelectionBoxModifier.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)

                Text("None: a plain mouse drag draws a selection box. Pick a modifier to keep plain drag as pan and require that key for the selection box. Two-finger trackpad always pans.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("View") {
                Stepper(value: $defaultZoom, in: 25...400, step: 25) {
                    LabeledContent("Default zoom level", value: "\(defaultZoom)%")
                }

                Toggle("Momentum panning", isOn: $momentumPanning)

                KeyboardShortcutRow(title: "Reset view", keys: ["⌘", "0"])
                KeyboardShortcutRow(title: "Zoom to fit", keys: ["⇧", "⌘", "0"])
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Spaces

private struct SpacesSettingsTab: View {
    @AppStorage("app.mode") private var appMode: AppMode = .canvas
    @AppStorage("spaces.defaultColumns") private var defaultColumns = 0   // 0 = auto
    @AppStorage("spaces.defaultRows") private var defaultRows = 0         // 0 = auto / no pagination

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Workspace mode", selection: $appMode) {
                    ForEach(AppMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Text("Canvas is the free pan/zoom board. Spaces tiles your cards full-screen over a background and is driven by the top space bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Spaces Layout") {
                Picker("Columns", selection: $defaultColumns) {
                    Text("Auto").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu)

                Picker("Rows", selection: $defaultRows) {
                    Text("Auto").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                .disabled(defaultColumns == 0)

                Text("Defaults for new spaces. A fixed columns × rows grid paginates overflow; each space can override this from its top bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Cards

private struct CardsSettingsTab: View {
    @AppStorage("cards.defaultWidth") private var defaultWidth = 320
    @AppStorage("cards.defaultHeight") private var defaultHeight = 240
    @AppStorage("cards.cornerRadius") private var cornerRadius = 12.0
    @AppStorage("cards.dropShadow") private var dropShadow = true
    @AppStorage("cards.doubleClickToEdit") private var doubleClickToEdit = true
    @AppStorage("cards.autoFocusNew") private var autoFocusNew = true
    @AppStorage("cards.bringToFront") private var bringToFront = true
    @AppStorage("cards.showCompleted") private var showCompleted = true
    @AppStorage("cards.strikeCompleted") private var strikeCompleted = true

    var body: some View {
        Form {
            Section("New Card Defaults") {
                Stepper(value: $defaultWidth, in: 200...800, step: 20) {
                    LabeledContent("Default width", value: "\(defaultWidth) pt")
                }

                Stepper(value: $defaultHeight, in: 120...600, step: 20) {
                    LabeledContent("Default height", value: "\(defaultHeight) pt")
                }

                LabeledContent("Corner radius") {
                    Slider(value: $cornerRadius, in: 0...24) {
                        Text("Corner radius")
                    } minimumValueLabel: {
                        Text("Sharp")
                    } maximumValueLabel: {
                        Text("Round")
                    }
                    .frame(width: 240)
                }

                Toggle("Drop shadow", isOn: $dropShadow)
            }

            Section("Behavior") {
                Toggle("Double-click to edit", isOn: $doubleClickToEdit)
                Toggle("Auto-focus new cards", isOn: $autoFocusNew)
                Toggle("Bring selected card to front", isOn: $bringToFront)
            }

            Section("Todo Cards") {
                Toggle("Show completed items", isOn: $showCompleted)
                Toggle("Strike through completed", isOn: $strikeCompleted)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - AI

private struct AISettingsTab: View {
    enum Memory: String, CaseIterable, Identifiable {
        case session = "Session only"
        case workspace = "Per workspace"
        var id: String { rawValue }
    }

    @AppStorage("ai.streamResponses") private var streamResponses = true
    @AppStorage("ai.memory") private var memory: Memory = .session
    @AppStorage("ai.sendSelectedCard") private var sendSelectedCard = true
    @AppStorage("ai.customInstructions") private var customInstructions = ""
    @AppStorage("agent.provider") private var agentProvider: MediatorAgentKind = .claudeCode
    @State private var persistConversations = false
    @EnvironmentObject private var modelAssets: ModelAssetManager

    var body: some View {
        Form {
            Section("Conversation") {
                Toggle("Stream responses", isOn: $streamResponses)

                Picker("Conversation memory", selection: $memory) {
                    ForEach(Memory.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Send selected card as context", isOn: $sendSelectedCard)
            }

            Section("Agents") {
                Picker("Delegation provider", selection: $agentProvider) {
                    ForEach(MediatorAgentKind.aiKinds) { Text($0.displayName).tag($0) }
                }
                Text("When you don't name an agent, Sunday delegates repo questions to this provider. Delegation uses your own account.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Launch commands") {
                    ForEach(MediatorAgentKind.aiKinds) { kind in
                        LaunchCommandRow(kind: kind)
                    }
                    Text("Run when you spawn that kind of agent — add flags here, e.g. \"claude --dangerously-skip-permissions\".")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("System Prompt") {
                LabeledContent("Custom instructions") {
                    TextEditor(text: $customInstructions)
                        .font(.body)
                        .frame(minHeight: 80)
                        .overlay(alignment: .topLeading) {
                            if customInstructions.isEmpty {
                                Text("Describe how the assistant should behave…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }

            VoiceSettingsSection()

            LocalAISettingsSection(assets: modelAssets, persistConversations: $persistConversations)
        }
        .formStyle(.grouped)
    }
}

/// A per-provider launch-command field. Its AppStorage key is derived from the
/// kind at init, so each provider persists its own override independently.
private struct LaunchCommandRow: View {
    let kind: MediatorAgentKind
    @AppStorage private var command: String

    init(kind: MediatorAgentKind) {
        self.kind = kind
        _command = AppStorage(wrappedValue: kind.defaultLaunchCommand ?? "", "agent.launch.\(kind.rawValue)")
    }

    var body: some View {
        LabeledContent(kind.displayName) {
            TextField(kind.defaultLaunchCommand ?? "", text: $command)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 240)
        }
    }
}

// MARK: - Storage

private struct StorageSettingsTab: View {
    @AppStorage("storage.autosave") private var autosave = true
    @AppStorage("storage.autosaveDelay") private var autosaveDelay = 0.75
    @AppStorage("storage.prettyPrint") private var prettyPrint = false

    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var sessionManager: AgentSessionManager

    @State private var showResetConfirmation = false
    @State private var showExportError = false
    @State private var exportErrorMessage = ""

    private var libraryURL: URL {
        WorkspaceStore.defaultLibraryURL()
    }

    private var dataFolder: String {
        libraryURL.deletingLastPathComponent().path
    }

    var body: some View {
        Form {
            Section("Location") {
                LabeledContent("Data folder") {
                    Text(dataFolder)
                        .textSelection(.enabled)
                        .font(.system(.caption, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([libraryURL])
                    }
                    .buttonStyle(.bordered)

                    Button("Change Location…") {
                        // Placeholder: opens an NSOpenPanel once relocation is supported.
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .help("Not supported yet — the data folder is fixed for now.")
                }
            }

            Section("Persistence") {
                Toggle("Autosave changes", isOn: $autosave)

                Stepper(value: $autosaveDelay, in: 0.25...5.0, step: 0.25) {
                    LabeledContent("Autosave delay", value: String(format: "%.2f s", autosaveDelay))
                }

                Toggle("Pretty-print JSON", isOn: $prettyPrint)
            }

            Section("Library") {
                LabeledContent("Workspaces", value: "\(store.library.workspaces.count)")
                LabeledContent("On-disk size", value: onDiskSize)

                HStack {
                    Button("Export Library…") { exportLibrary() }
                        .buttonStyle(.bordered)

                    Button("Reset All Data…") { showResetConfirmation = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reset all data?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) {
                sessionManager.terminateAllSessions()
                store.resetAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes every workspace, backup, and imported background, then starts over with one empty space. This cannot be undone.")
        }
        .alert("Export failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    /// Zips the whole data folder (library.json + workspaces/ + backups/ +
    /// backgrounds/) to a user-chosen destination and reveals it in Finder.
    private func exportLibrary() {
        store.flushPendingPersistence()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "Voidloom-Export.zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let source = libraryURL.deletingLastPathComponent()
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-c", "-k", "--sequesterRsrc", source.path, destination.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            exportErrorMessage = error.localizedDescription
            showExportError = true
        }
    }

    private var onDiskSize: String {
        let base = libraryURL.deletingLastPathComponent()
        guard let enumerator = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]
        ) else { return "—" }
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            bytes += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
                .totalFileAllocatedSize) ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        Form {
            Section("Voidloom") {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                        .resizable()
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voidloom")
                            .font(.title2.weight(.semibold))
                        Text("Canvas-first agent workspace")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)

                Button("Check for Updates") {
                    // Placeholder: no updater backend yet.
                }
                .buttonStyle(.borderedProminent)
                .disabled(true)
            }

            Section("Resources") {
                Button("Release notes") {
                    // Placeholder: opens changelog.
                }
                .buttonStyle(.link)

                Button("Acknowledgements") {
                    // Placeholder: opens open-source licenses sheet.
                }
                .buttonStyle(.link)

                Button("Report an issue") {
                    // Placeholder: opens issue tracker.
                }
                .buttonStyle(.link)
            }

            Section("Legal") {
                LabeledContent("Made by", value: "Roshan")
                LabeledContent("Copyright", value: "© 2026 Voidloom. All rights reserved.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Keyboard Shortcut Row

/// Read-only shortcut display: a label plus bordered key-cap capsules.
private struct KeyboardShortcutRow: View {
    let title: String
    let keys: [String]

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .frame(minWidth: 20)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor))
                        )
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ModelAssetManager())
}
