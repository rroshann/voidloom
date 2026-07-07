import Speech
import SwiftUI
import VoidloomCore

/// Voice input preferences: mode, wake phrase, and on-device honesty copy.
struct VoiceSettingsSection: View {
    @AppStorage("voice.mode") private var voiceMode: VoiceInputMode = .pushToTalk
    @AppStorage("voice.wakePhrase") private var wakePhrase = "hey sunday"
    @AppStorage("voice.useSpeechAnalyzer") private var useSpeechAnalyzer = false
    @AppStorage("voice.speakReplies") private var speakReplies = false

    private var speechEngineLabel: String {
        switch voiceMode {
        case .alwaysListening:
            return "Parakeet (wake phrase + continuous listening)"
        case .pushToTalk:
            if useSpeechAnalyzer, speechAnalyzerAvailable {
                return "Apple SpeechAnalyzer (push-to-talk, experimental)"
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

            Toggle("Speak \(AssistantIdentity.name)'s replies", isOn: $speakReplies)
            if speakReplies {
                Text("\(AssistantIdentity.name) reads answers aloud on-device. It stops the moment you start speaking, and never talks over you.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

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

            if voiceMode == .pushToTalk, speechAnalyzerAvailable {
                Toggle("Use Apple speech recognition (experimental)", isOn: $useSpeechAnalyzer)
                Text(
                    "Experimental on this OS — Apple's on-device Speech framework may be unstable. Parakeet is recommended."
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            if voiceMode != .off {
                Text("Voice commands are English-only in this version.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if voiceMode == .alwaysListening || !useSpeechAnalyzer || voiceMode == .off {
                Text(
                    "Parakeet (parakeet-realtime-eou-120m-coreml) under the NVIDIA Open Model License."
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var speechAnalyzerAvailable: Bool {
        guard #available(macOS 26, *) else { return false }
        return SpeechTranscriber.isAvailable
    }
}
