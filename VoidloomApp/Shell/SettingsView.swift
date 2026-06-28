import SwiftUI
import VoidloomCore

struct SettingsView: View {
    @AppStorage("isWorkspaceSidebarVisible") private var isWorkspaceSidebarVisible = false

    private var storageLocation: String {
        WorkspaceStore.defaultLibraryURL()
            .deletingLastPathComponent()
            .path
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show workspaces sidebar", isOn: $isWorkspaceSidebarVisible)
            }

            Section("Storage") {
                LabeledContent("Data folder") {
                    Text(storageLocation)
                        .textSelection(.enabled)
                        .font(.system(.caption, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("About") {
                LabeledContent("Version", value: "0.1")
                LabeledContent("App", value: "Voidloom")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 280)
    }
}

#Preview {
    SettingsView()
}
