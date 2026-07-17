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
    @AppStorage(AssistantVoice.defaultsKey) private var assistantVoice: AssistantVoice = .female
    @EnvironmentObject private var speaker: AssistantSpeaker

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
                LabeledContent("\(AssistantIdentity.name)'s voice") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(AssistantVoice.allCases) { voice in
                            HStack(spacing: 10) {
                                Button {
                                    assistantVoice = voice
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: assistantVoice == voice
                                              ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(assistantVoice == voice
                                                             ? Color.accentColor : .secondary)
                                        Text("\(voice.displayName) (American)")
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(assistantVoice == voice ? .isSelected : [])

                                Button {
                                    speaker.togglePreview(voice)
                                } label: {
                                    Image(systemName: speaker.previewingVoice == voice
                                          ? "stop.fill" : "play.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(.quaternary))
                                }
                                .buttonStyle(.plain)
                                .help(speaker.previewingVoice == voice
                                      ? "Stop preview" : "Preview this voice")
                                .accessibilityLabel(speaker.previewingVoice == voice
                                                    ? "Stop preview" : "Preview \(voice.displayName) voice")
                            }
                        }
                    }
                }
                Text("Natural American neural voices, generated fully on this Mac. The voice downloads on first use; until then the best installed system voice fills in.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Toggle("Show reply text while speaking", isOn: $showTextReplies)
                Text(showTextReplies
                     ? "When you speak to \(AssistantIdentity.name), the reply appears as text and is read aloud."
                     : "Pure voice: when you speak to \(AssistantIdentity.name), it replies by voice only — no text bubble.")
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
