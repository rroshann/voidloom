import Speech
import SwiftUI
import VoidloomCore

/// Voice input preferences: mode, wake phrase, and on-device honesty copy.
struct VoiceSettingsSection: View {
    @AppStorage("voice.mode") private var voiceMode: VoiceInputMode = .pushToTalk
    @AppStorage("voice.wakePhrase") private var wakePhrase = "hey voidloom"

    private var speechEngineLabel: String {
        switch voiceMode {
        case .alwaysListening:
            return "Parakeet (wake phrase + continuous listening)"
        case .pushToTalk:
            if #available(macOS 26, *), SpeechTranscriber.isAvailable {
                return "Apple SpeechAnalyzer (push-to-talk)"
            }
            return "Parakeet (push-to-talk)"
        case .off:
            return "Off"
        }
    }

    var body: some View {
        Section("Voice") {
            Picker("Input mode", selection: $voiceMode) {
                ForEach(VoiceInputMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Speech engine", value: speechEngineLabel)

            if voiceMode == .alwaysListening {
                TextField("Wake phrase", text: $wakePhrase)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: wakePhrase) { _, newValue in
                        wakePhrase = newValue.lowercased()
                    }

                Text(
                    "Always listening keeps the microphone (and the orange indicator) on whenever Voidloom runs. Audio never leaves this Mac."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if voiceMode != .off {
                Text("Voice commands are English-only in this version.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if voiceMode == .alwaysListening || !speechAnalyzerActive {
                Text(
                    "Parakeet (parakeet-realtime-eou-120m-coreml) under the NVIDIA Open Model License."
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            if speechAnalyzerActive && voiceMode == .pushToTalk {
                Text(
                    "Push-to-talk uses Apple's on-device Speech framework when available; always-listening stays on Parakeet for wake-phrase support."
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var speechAnalyzerActive: Bool {
        guard #available(macOS 26, *) else { return false }
        return SpeechTranscriber.isAvailable
    }
}
