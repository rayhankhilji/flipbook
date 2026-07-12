import Foundation

/// A single turn in a conversation with Claude.
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
    case missingKey
    case http(status: Int, message: String)
    case decoding
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No Anthropic API key set. Add one in Settings → AI."
        case .http(let status, let message):
            return "Anthropic API error (\(status)): \(message)"
        case .decoding:
            return "Couldn't read the response from Anthropic."
        case .network(let detail):
            return "Network problem talking to Anthropic: \(detail)"
        }
    }
}

/// Talks to the Anthropic Messages API directly over HTTPS. There is no official
/// Anthropic SDK for Swift, so this speaks the raw REST + SSE protocol
/// (`x-api-key`, `anthropic-version: 2023-06-01`, `stream: true`). Bring-your-own-key:
/// the key is read from the Keychain per call, never cached in memory longer than a request.
public actor AIService {
    public static let shared = AIService()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

    public init() {}

    // MARK: - Streaming chat

    /// Streams Claude's reply token-by-token. `system` sets the persona/instructions;
    /// `history` is the full prior conversation (the API is stateless, so send it every time).
    public func streamReply(
        system: String?,
        history: [AIChatMessage],
        modelID: String,
        maxTokens: Int = 4096,
        webSearch: Bool = false
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = AIKeychain.load() else {
                        throw AIServiceError.missingKey
                    }
                    let request = try makeRequest(
                        key: key,
                        system: system,
                        history: history,
                        modelID: modelID,
                        maxTokens: maxTokens,
                        webSearch: webSearch,
                        stream: true
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        // Error bodies aren't SSE — drain and surface the message.
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw AIServiceError.http(status: http.statusCode, message: Self.extractError(from: body))
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: data)
                        else { continue }

                        switch event.type {
                        case "content_block_delta":
                            if let text = event.delta?.text, !text.isEmpty {
                                continuation.yield(text)
                            }
                        case "message_stop":
                            continuation.finish()
                            return
                        case "error":
                            throw AIServiceError.http(status: 200, message: event.error?.message ?? "streaming error")
                        default:
                            break
                        }
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

    // MARK: - One-shot completion (summaries, notes)

    /// Non-streaming single reply — for short, self-contained tasks like summarizing a page.
    public func complete(
        system: String?,
        prompt: String,
        modelID: String,
        maxTokens: Int = 1024
    ) async throws -> String {
        guard let key = AIKeychain.load() else { throw AIServiceError.missingKey }
        let request = try makeRequest(
            key: key,
            system: system,
            history: [AIChatMessage(role: .user, text: prompt)],
            modelID: modelID,
            maxTokens: maxTokens,
            webSearch: false,
            stream: false
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.http(status: http.statusCode, message: Self.extractError(from: body))
        }
        guard let message = try? JSONDecoder().decode(MessageResponse.self, from: data) else {
            throw AIServiceError.decoding
        }
        return message.content.compactMap { $0.text }.joined()
    }

    /// Cheap connectivity/auth check used by the Settings "Test connection" button.
    public func validateKey(modelID: String) async throws {
        _ = try await complete(system: nil, prompt: "Reply with the single word: ok", modelID: modelID, maxTokens: 16)
    }

    // MARK: - Request building

    private func makeRequest(
        key: String,
        system: String?,
        history: [AIChatMessage],
        modelID: String,
        maxTokens: Int,
        webSearch: Bool,
        stream: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": modelID,
            "max_tokens": maxTokens,
            "stream": stream,
            "messages": history.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        if let system, !system.isEmpty {
            body["system"] = system
        }
        if webSearch {
            body["tools"] = [["type": "web_search_20260209", "name": "web_search"]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func extractError(from body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return body.isEmpty ? "Unknown error" : body }
        return message
    }

    // MARK: - Wire types

    private struct StreamEvent: Decodable {
        let type: String
        let delta: Delta?
        let error: APIError?

        struct Delta: Decodable {
            let text: String?
        }
        struct APIError: Decodable {
            let message: String?
        }
    }

    private struct MessageResponse: Decodable {
        let content: [Block]
        struct Block: Decodable {
            let type: String
            let text: String?
        }
    }
}
