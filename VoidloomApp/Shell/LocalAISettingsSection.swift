import SwiftUI
import VoidloomAI
import VoidloomCore

/// Real "Local AI" management: tier status, per-model download/verify with
/// progress, and license attribution. Drives `ModelAssetManager`; no inference here.
struct LocalAISettingsSection: View {
    @ObservedObject var assets: ModelAssetManager
    @Binding var persistConversations: Bool
    @AppStorage("ai.preferAppleIntelligence") private var preferAppleIntelligence = true

    private var statusText: String {
        let commandReady = assets.state(of: LocalModelManifest.commandModel) == .ready
        let chatReady = assets.state(of: LocalModelManifest.chatModel) == .ready
        let fmActive = AppleTierAvailability.foundationModelsAvailable && preferAppleIntelligence

        if commandReady {
            var parts = ["Fast path + local LLM commands"]
            if fmActive { parts.append("+ Apple Intelligence chat") }
            else if chatReady { parts.append("+ local chat") }
            return parts.joined(separator: " ")
        }

        if fmActive {
            return "Apple Intelligence + fast path"
        }

        if !commandReady && !chatReady {
            return "Fast path only (instant parser)"
        }
        var parts = ["Fast path"]
        if chatReady { parts.append("+ local chat") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        Section("Local AI") {
            LabeledContent("Status", value: statusText)

            if AppleTierAvailability.foundationModelsAvailable {
                Toggle(
                    "Use Apple Intelligence for chat, and for commands whenever the fast local command model is not downloaded.",
                    isOn: $preferAppleIntelligence
                )
                Text("When the command model is downloaded, commands always use the faster local LLM. Takes effect on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Downloaded models take effect the next time Voidloom launches.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Voidloom's AI runs entirely on this Mac — no endpoints, no API keys.")
                .font(.callout)
                .foregroundStyle(.secondary)

            modelRow(LocalModelManifest.commandModel, subtitle: "Primary command parser when downloaded (meets the ≤1s latency bar).")
            modelRow(LocalModelManifest.chatModel, subtitle: "Optional. Fallback chat when Apple Intelligence is off or unavailable.")

            Toggle("Remember conversations across launches", isOn: $persistConversations)
            Text(persistConversations
                 ? "Each workspace's chat with \(AssistantIdentity.name) is saved on-device and restored when you reopen the app. Clear a conversation any time from the assistant sidebar."
                 : "Conversations stay only for this session and are erased when you quit. Any saved history is removed.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
