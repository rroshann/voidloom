import AppKit
import Speech
import SwiftUI
import VoidloomCore

/// Voice input preferences: mode, wake phrase, and on-device honesty copy.
struct VoiceSettingsSection: View {
    @AppStorage("voice.mode") private var voiceMode: VoiceInputMode = .pushToTalk
    @AppStorage("voice.wakePhrase") private var wakePhrase = "hey sunday"
    @AppStorage("voice.useSpeechAnalyzer") private var useSpeechAnalyzer = false
    @AppStorage("voice.speechMode") private var speechMode: AssistantSpeechMode = .whenSpokenTo
    @AppStorage("voice.showTextReplies") private var showTextReplies = true

    private var speechModeExplanation: String {
        switch speechMode {
        case .off: "\(AssistantIdentity.name) never reads replies aloud."
        case .whenSpokenTo: "\(AssistantIdentity.name) speaks back only when you talk to it — a natural spoken conversation. Typed replies stay silent."
        case .always: "\(AssistantIdentity.name) reads every reply aloud, whether you typed or spoke."
        }
    }

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

            Picker("Speak replies", selection: $speechMode) {
                ForEach(AssistantSpeechMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(speechModeExplanation)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if speechMode != .off {
                Toggle("Show reply text while speaking", isOn: $showTextReplies)
                Text(showTextReplies
                     ? "When you speak to \(AssistantIdentity.name), the reply appears as text and is read aloud."
                     : "Pure voice: when you speak to \(AssistantIdentity.name), it replies by voice only — no text bubble.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if AssistantSpeaker.hasEnhancedEnglishVoice {
                    Text("Voices are on-device and free — \(AssistantIdentity.name) automatically uses the most natural English voice installed.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    // No Enhanced/Premium English voice installed → narration is stuck on
                    // the robotic default tier. Tell the user why, with one click to fix it.
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Make \(AssistantIdentity.name) sound natural", systemImage: "waveform.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("Only default-quality English voices are installed, so \(AssistantIdentity.name) sounds synthetic. Install an Enhanced or Premium English voice (e.g. “Samantha (Enhanced)”) and \(AssistantIdentity.name) uses it automatically — no restart needed.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("Open Spoken Content Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption2)
                        .buttonStyle(.link)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.08)))
                }
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
