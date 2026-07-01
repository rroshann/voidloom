import Foundation
import VoidloomCore

/// The user-selectable Claude model for the AI sidebar. Raw values are the
/// display names shown in Settings; `apiModelID` is the wire ID.
enum AIModelChoice: String, CaseIterable, Identifiable {
    case opus = "Claude Opus 4.8"
    case sonnet = "Claude Sonnet 5"
    case haiku = "Claude Haiku 4.5"

    var id: String { rawValue }

    var apiModelID: String {
        switch self {
        case .opus: return "claude-opus-4-8"
        case .sonnet: return "claude-sonnet-5"
        case .haiku: return "claude-haiku-4-5"
        }
    }
}

/// Real AI backend: streams responses from the Anthropic Messages API (SSE).
/// While no API key is stored, delegates to the stub so the sidebar keeps its
/// "backend isn't connected" affordance; adding a key in Settings → AI makes
/// the very next message go to the real API — no relaunch needed.
@MainActor
final class AnthropicResponseProvider: ResponseProvider {
    private let noKeyFallback = StubResponseProvider()

    func generateResponse(
        workspaceID: UUID,
        userMessage: String,
        context: String?,
        onStreamChunk: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard let apiKey = AnthropicAPIKeyStore.load() else {
            noKeyFallback.generateResponse(
                workspaceID: workspaceID, userMessage: userMessage, context: context,
                onStreamChunk: onStreamChunk, onComplete: onComplete, onError: onError
            )
            return
        }

        let request = buildRequest(apiKey: apiKey, userMessage: userMessage, context: context)
        let streamToUI = UserDefaults.standard.object(forKey: "ai.streamResponses") as? Bool ?? true

        Task { @MainActor in
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard http.statusCode == 200 else {
                    var body = Data()
                    for try await byte in bytes { body.append(byte) }
                    onError(Self.apiErrorMessage(from: body, status: http.statusCode))
                    return
                }

                var full = ""
                var stopReason: String?
                for try await line in bytes.lines {
                    guard line.hasPrefix("data: "),
                          let event = try? JSONSerialization.jsonObject(
                            with: Data(line.dropFirst(6).utf8)) as? [String: Any],
                          let type = event["type"] as? String else { continue }

                    switch type {
                    case "content_block_delta":
                        if let delta = event["delta"] as? [String: Any],
                           delta["type"] as? String == "text_delta",
                           let text = delta["text"] as? String {
                            full += text
                            if streamToUI { onStreamChunk(text) }
                        }
                    case "message_delta":
                        if let delta = event["delta"] as? [String: Any] {
                            stopReason = delta["stop_reason"] as? String
                        }
                    case "error":
                        let message = (event["error"] as? [String: Any])?["message"] as? String
                        onError(message ?? "The API returned an error.")
                        return
                    default:
                        break
                    }
                }

                if stopReason == "refusal", full.isEmpty {
                    onError("Claude declined this request.")
                } else {
                    onComplete(full)
                }
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    private func buildRequest(apiKey: String, userMessage: String, context: String?) -> URLRequest {
        let modelName = UserDefaults.standard.string(forKey: "ai.model")
        let model = AIModelChoice(rawValue: modelName ?? "") ?? .opus

        var system = "You are the assistant inside Voidloom, a canvas workspace app. Be concise and helpful."
        let custom = UserDefaults.standard.string(forKey: "ai.customInstructions") ?? ""
        if !custom.isEmpty { system += "\n\n" + custom }

        var content = userMessage
        if let context, !context.isEmpty {
            content = "<card_context>\n\(context)\n</card_context>\n\n\(userMessage)"
        }

        let body: [String: Any] = [
            "model": model.apiModelID,
            "max_tokens": 64000,
            "stream": true,
            "thinking": ["type": "adaptive"],
            "system": system,
            "messages": [["role": "user", "content": content]]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func apiErrorMessage(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        switch status {
        case 401: return "Invalid API key — check Settings → AI."
        case 429: return "Rate limited — wait a moment and retry."
        default: return "The API returned HTTP \(status)."
        }
    }
}
