import SwiftUI
import VoidloomAI

/// Real "Local AI" management: tier status, per-model download/verify with
/// progress, and license attribution. Drives `ModelAssetManager`; no inference here.
struct LocalAISettingsSection: View {
    @ObservedObject var assets: ModelAssetManager
    @Binding var persistConversations: Bool

    private var statusText: String {
        let commandReady = assets.state(of: LocalModelManifest.commandModel) == .ready
        let chatReady = assets.state(of: LocalModelManifest.chatModel) == .ready
        if !commandReady && !chatReady {
            return "Fast path only (instant parser)"
        }
        var parts = ["Fast path"]
        if commandReady { parts.append("+ local LLM commands") }
        if chatReady { parts.append("+ local chat") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        Section("Local AI") {
            LabeledContent("Status", value: statusText)
            Text("Downloaded models take effect the next time Voidloom launches.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Voidloom's AI runs entirely on this Mac — no endpoints, no API keys.")
                .font(.callout)
                .foregroundStyle(.secondary)

            modelRow(LocalModelManifest.commandModel, subtitle: "Required for natural-language commands.")
            modelRow(LocalModelManifest.chatModel, subtitle: "Optional. Enables local chat replies; without it, chat uses placeholder responses.")

            Toggle("Persist conversations to disk", isOn: $persistConversations)
                .disabled(true)
        }
    }

    @ViewBuilder
    private func modelRow(_ asset: LocalModelAsset, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.displayName).font(.body)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    Text("License: \(asset.license) · \(ByteCountFormatter.string(fromByteCount: asset.sizeBytes, countStyle: .file))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                control(for: asset)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func control(for asset: LocalModelAsset) -> some View {
        switch assets.state(of: asset) {
        case .ready:
            HStack(spacing: 8) {
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Verify") { Task { _ = await assets.verifyExisting(asset) } }
                    .controlSize(.small)
            }
        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress).frame(width: 80)
                Button("Cancel") { assets.cancel(asset) }
            }
        case .verifying:
            ProgressView().controlSize(.small)
        case .failed(let reason):
            VStack(alignment: .trailing) {
                Button("Retry") { Task { try? await assets.download(asset) } }
                Text(reason).font(.caption2).foregroundStyle(.red)
            }
        case .missing:
            Button("Download") { Task { try? await assets.download(asset) } }
        }
    }
}
