import Foundation

/// A single turn in a conversation.
public struct AIChatMessage: Identifiable, Sendable, Hashable, Codable {
    public enum Role: String, Sendable, Codable {
        case user
        case assistant
    }

    public let id: UUID
    public var role: Role
    public var text: String

    public init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

public enum AIServiceError: LocalizedError {
    case missingKey(AIProvider)
    case http(status: Int, message: String)
    case decoding
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey(let provider):
            return "No API key set for \(provider.displayName). Add one in Settings → AI."
        case .http(let status, let message):
            return "API error (\(status)): \(message)"
        case .decoding:
            return "Couldn't read the response."
        case .network(let detail):
            return "Network problem: \(detail)"
        }
    }
}

/// Talks to AI providers directly over HTTPS. No official SDK exists for Swift, so this
/// speaks the raw REST + SSE protocols: Anthropic's Messages API for Claude, and OpenAI
/// Chat Completions for OpenAI, Gemini, and YUNWU (one shared code path). Keys are read
/// from the Keychain per call, per provider — never held in memory beyond a request.
public actor AIService {
    public static let shared = AIService()

    private let anthropicVersion = "2023-06-01"

    public init() {}

    // MARK: - Streaming chat

    public func streamReply(
        provider: AIProvider,
        system: String?,
        history: [AIChatMessage],
        modelID: String,
        maxTokens: Int = 4096
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = AIKeychain.load(for: provider) else {
                        throw AIServiceError.missingKey(provider)
                    }
                    let request = try makeRequest(
                        provider: provider, key: key, system: system, history: history,
                        modelID: modelID, maxTokens: maxTokens, stream: true
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        // Error bodies aren't SSE — drain and surface the message.
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw AIServiceError.http(status: http.statusCode, message: Self.extractError(from: body))
                    }

                    for try await line in bytes.lines {
                        guard let text = Self.parseStreamLine(line, wire: provider.wire) else { continue }
                        if text == Self.doneSentinel {
                            continuation.finish()
                            return
                        }
                        if !text.isEmpty { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as AIServiceError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AIServiceError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - One-shot completion (summaries, key validation)

    public func complete(
        provider: AIProvider,
        system: String?,
        prompt: String,
        modelID: String,
        maxTokens: Int = 1024
    ) async throws -> String {
        guard let key = AIKeychain.load(for: provider) else { throw AIServiceError.missingKey(provider) }
        let request = try makeRequest(
            provider: provider, key: key, system: system,
            history: [AIChatMessage(role: .user, text: prompt)],
            modelID: modelID, maxTokens: maxTokens, stream: false
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.http(status: http.statusCode, message: Self.extractError(from: body))
        }
        guard let text = Self.parseCompletion(data, wire: provider.wire) else {
            throw AIServiceError.decoding
        }
        return text
    }

    /// Cheap connectivity/auth check for the Settings "Test connection" button.
    public func validateKey(provider: AIProvider, modelID: String) async throws {
        _ = try await complete(
            provider: provider, system: nil,
            prompt: "Reply with the single word: ok", modelID: modelID, maxTokens: 16
        )
    }

    // MARK: - Request building

    private func makeRequest(
        provider: AIProvider, key: String, system: String?, history: [AIChatMessage],
        modelID: String, maxTokens: Int, stream: Bool
    ) throws -> URLRequest {
        switch provider.wire {
        case .anthropic:
            var request = URLRequest(url: provider.baseURL.appendingPathComponent("v1/messages"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

            var body: [String: Any] = [
                "model": modelID,
                "max_tokens": maxTokens,
                "stream": stream,
                "messages": history.map { ["role": $0.role.rawValue, "content": $0.text] },
            ]
            if let system, !system.isEmpty { body["system"] = system }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            return request

        case .openAICompatible:
            var request = URLRequest(url: provider.baseURL.appendingPathComponent("chat/completions"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

            // OpenAI carries the system prompt as a leading `system` message.
            var messages: [[String: Any]] = []
            if let system, !system.isEmpty {
                messages.append(["role": "system", "content": system])
            }
            messages += history.map { ["role": $0.role.rawValue, "content": $0.text] }

            let body: [String: Any] = [
                "model": modelID,
                "max_tokens": maxTokens,
                "stream": stream,
                "messages": messages,
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            return request
        }
    }

    // MARK: - Response parsing

    private static let doneSentinel = "\u{0}__DONE__"

    /// Returns the text delta from one SSE line, `doneSentinel` when the stream ends, or nil.
    private static func parseStreamLine(_ line: String, wire: AIProvider.Wire) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty { return nil }
        if payload == "[DONE]" { return doneSentinel }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        switch wire {
        case .anthropic:
            let type = json["type"] as? String
            if type == "message_stop" { return doneSentinel }
            if type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                return text
            }
            return nil
        case .openAICompatible:
            guard let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any]
            else { return nil }
            return delta["content"] as? String
        }
    }

    private static func parseCompletion(_ data: Data, wire: AIProvider.Wire) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch wire {
        case .anthropic:
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            return content.compactMap { $0["text"] as? String }.joined()
        case .openAICompatible:
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any]
            else { return nil }
            return message["content"] as? String
        }
    }

    private static func extractError(from body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return body.isEmpty ? "Unknown error" : body }
        return message
    }
}
