import Foundation

/// An AI backend Flipbook can talk to. Anthropic uses its native Messages API; the other
/// three are OpenAI-Chat-Completions compatible and share one client — they differ only in
/// base URL, key, and model list. (Gemini exposes an OpenAI-compatible endpoint at
/// `/v1beta/openai`; YUNWU is an OpenAI-compatible relay in front of 200+ models.)
public enum AIProvider: String, Sendable, Codable, CaseIterable, Identifiable {
    case anthropic
    case openai
    case gemini
    case yunwu

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic (Claude)"
        case .openai: "OpenAI"
        case .gemini: "Google Gemini"
        case .yunwu: "YUNWU (云雾)"
        }
    }

    /// Whether the wire protocol is Anthropic's Messages API or OpenAI Chat Completions.
    public enum Wire: Sendable { case anthropic, openAICompatible }

    public var wire: Wire {
        switch self {
        case .anthropic: .anthropic
        case .openai, .gemini, .yunwu: .openAICompatible
        }
    }

    /// Base URL that `v1/messages` (Anthropic) or `chat/completions` (OpenAI-style) hangs off.
    public var baseURL: URL {
        switch self {
        case .anthropic: URL(string: "https://api.anthropic.com")!
        case .openai: URL(string: "https://api.openai.com/v1")!
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
        case .yunwu: URL(string: "https://yunwu.ai/v1")!
        }
    }

    /// Where the user gets a key, surfaced as a Settings link.
    public var consoleURL: URL {
        switch self {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        case .yunwu: URL(string: "https://yunwu.ai")!
        }
    }

    public var keyPlaceholder: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openai: "sk-…"
        case .gemini: "AIza…"
        case .yunwu: "sk-…"
        }
    }

    public var note: String {
        switch self {
        case .anthropic: "Claude models, billed directly by Anthropic."
        case .openai: "GPT and o-series models, billed by OpenAI."
        case .gemini: "Gemini models via Google's OpenAI-compatible endpoint."
        case .yunwu: "One key, 200+ models (GPT/Claude/Gemini/…). Any model ID it supports works."
        }
    }

    public var defaultModelID: String { models.first?.id ?? "" }

    /// The cheapest capable model for bulk work. Book distillation reads an entire book —
    /// hundreds of thousands of tokens — so the map phase runs here rather than on the
    /// flagship, which is what makes distilling a full book cost cents instead of dollars.
    public var bulkModelID: String {
        switch self {
        case .anthropic: "claude-haiku-4-5-20251001"
        case .openai: "gpt-5-mini"
        case .gemini: "gemini-2.5-flash"
        case .yunwu: "gemini-2.5-flash"
        }
    }

    /// Presets shown in the model menu. The model field stays free-text everywhere, so a
    /// newly released model can be used the day it ships without an app update.
    public var models: [AIModelOption] {
        switch self {
        case .anthropic:
            return [
                AIModelOption(id: "claude-opus-5", name: "Claude Opus 5", blurb: "Most capable — best for deep author conversations."),
                AIModelOption(id: "claude-sonnet-5", name: "Claude Sonnet 5", blurb: "Fast and strong — lower-cost everyday choice."),
                AIModelOption(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5", blurb: "Fastest and cheapest — quick summaries."),
            ]
        case .openai:
            return [
                AIModelOption(id: "gpt-5", name: "GPT-5", blurb: "OpenAI's most capable model."),
                AIModelOption(id: "gpt-5-mini", name: "GPT-5 mini", blurb: "Smaller, faster, cheaper GPT-5."),
                AIModelOption(id: "gpt-4o", name: "GPT-4o", blurb: "Fast multimodal workhorse."),
                AIModelOption(id: "o4-mini", name: "o4-mini", blurb: "Reasoning model, cost-efficient."),
            ]
        case .gemini:
            return [
                AIModelOption(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", blurb: "Google's most capable Gemini."),
                AIModelOption(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", blurb: "Fast and cost-efficient."),
                AIModelOption(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", blurb: "Lightweight, very fast."),
            ]
        case .yunwu:
            return [
                AIModelOption(id: "gpt-5", name: "GPT-5 (via YUNWU)", blurb: "OpenAI GPT-5 through the relay."),
                AIModelOption(id: "claude-opus-5", name: "Claude Opus 5 (via YUNWU)", blurb: "Claude through the relay."),
                AIModelOption(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro (via YUNWU)", blurb: "Gemini through the relay."),
                AIModelOption(id: "deepseek-chat", name: "DeepSeek Chat (via YUNWU)", blurb: "DeepSeek through the relay."),
            ]
        }
    }
}

/// One selectable model within a provider. IDs are the exact wire model strings.
public struct AIModelOption: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let blurb: String

    public init(id: String, name: String, blurb: String) {
        self.id = id
        self.name = name
        self.blurb = blurb
    }
}

/// Lookups across every provider's catalog.
public enum AIModelCatalog {
    public static let defaultModelID = AIProvider.anthropic.defaultModelID

    /// Display metadata for a model ID, falling back to the raw ID for custom entries.
    public static func option(for id: String) -> AIModelOption {
        for provider in AIProvider.allCases {
            if let match = provider.models.first(where: { $0.id == id }) { return match }
        }
        return AIModelOption(id: id, name: id, blurb: "")
    }
}
