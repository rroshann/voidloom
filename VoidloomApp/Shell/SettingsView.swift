import SwiftUI
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
    @AppStorage("isWorkspaceSidebarVisible") private var isWorkspaceSidebarVisible = false

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
                Toggle("Show workspaces sidebar", isOn: $isWorkspaceSidebarVisible)
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
    @AppStorage("appearance.mode") private var appearanceMode: AppearanceMode = .system
    @State private var accentColor: Color = .accentColor
    @AppStorage("appearance.reduceTransparency") private var reduceTransparency = false
    @AppStorage("appearance.canvasBackground") private var canvasBackground: CanvasBackground = .dots
    @AppStorage("appearance.backgroundContrast") private var backgroundContrast = 0.35
    @AppStorage("appearance.showVignette") private var showVignette = false
    @AppStorage("appearance.textSize") private var textSize: TextSize = .medium
    @AppStorage("appearance.monospacedMetadata") private var monospacedMetadata = true

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)

                ColorPicker("Accent color", selection: $accentColor, supportsOpacity: false)

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

// MARK: - Canvas

private struct CanvasSettingsTab: View {
    @AppStorage("canvas.scrollZooms") private var scrollZooms = true
    @AppStorage("canvas.invertPan") private var invertPan = false
    @AppStorage("canvas.zoomSensitivity") private var zoomSensitivity = 1.0
    @AppStorage("canvas.zoomTowardCursor") private var zoomTowardCursor = true
    @AppStorage("canvas.snapToGrid") private var snapToGrid = false
    @AppStorage("canvas.gridSize") private var gridSize = 16
    @AppStorage("canvas.showAlignmentGuides") private var showAlignmentGuides = true
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

            Section("Grid & Snapping") {
                Toggle("Snap cards to grid", isOn: $snapToGrid)

                Stepper(value: $gridSize, in: 8...64, step: 4) {
                    LabeledContent("Grid size", value: "\(gridSize) pt")
                }
                .disabled(!snapToGrid)

                Toggle("Show alignment guides", isOn: $showAlignmentGuides)
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
    enum Model: String, CaseIterable, Identifiable {
        case opus = "Claude Opus 4.x"
        case sonnet = "Claude Sonnet 4.x"
        case haiku = "Claude Haiku"
        var id: String { rawValue }
    }

    enum Memory: String, CaseIterable, Identifiable {
        case session = "Session only"
        case workspace = "Per workspace"
        var id: String { rawValue }
    }

    @AppStorage("ai.model") private var model: Model = .sonnet
    @AppStorage("ai.streamResponses") private var streamResponses = true
    @AppStorage("ai.memory") private var memory: Memory = .session
    @AppStorage("ai.sendSelectedCard") private var sendSelectedCard = true
    @AppStorage("ai.customInstructions") private var customInstructions = ""
    @State private var apiEndpoint = ""
    @State private var apiKey = ""
    @State private var persistConversations = false

    var body: some View {
        Form {
            Section("Conversation") {
                Picker("Default model", selection: $model) {
                    ForEach(Model.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)

                Toggle("Stream responses", isOn: $streamResponses)

                Picker("Conversation memory", selection: $memory) {
                    ForEach(Memory.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Send selected card as context", isOn: $sendSelectedCard)
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

            Section("Connection") {
                TextField("API endpoint", text: $apiEndpoint, prompt: Text("https://api.anthropic.com"))
                    .disabled(true)

                SecureField("API key", text: $apiKey, prompt: Text("••••••••"))
                    .disabled(true)

                Toggle("Persist conversations to disk", isOn: $persistConversations)
                    .disabled(true)

                Text("Conversations are session-only in this build.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Storage

private struct StorageSettingsTab: View {
    @AppStorage("storage.autosave") private var autosave = true
    @AppStorage("storage.autosaveDelay") private var autosaveDelay = 0.75
    @AppStorage("storage.prettyPrint") private var prettyPrint = false

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
                LabeledContent("Workspaces", value: "—")
                LabeledContent("On-disk size", value: "—")

                HStack {
                    Button("Export Library…") {
                        // Placeholder: zips library.json + workspaces/.
                    }
                    .buttonStyle(.bordered)

                    Button("Reset All Data…") {
                        // Placeholder: destructive reset behind a confirmation sheet.
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .formStyle(.grouped)
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
}
