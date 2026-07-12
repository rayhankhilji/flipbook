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

    /// The base URL that `/v1/messages` (Anthropic) or `/chat/completions` (OpenAI-style)
    /// is appended to.
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

    /// Placeholder shown in the key field, hinting at each provider's key format.
    public var keyPlaceholder: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openai: "sk-…"
        case .gemini: "AIza…"
        case .yunwu: "sk-…"
        }
    }

    /// A one-line note about the provider, shown under the picker.
    public var note: String {
        switch self {
        case .anthropic:
            "Claude models, billed directly by Anthropic."
        case .openai:
            "GPT and o-series models, billed by OpenAI."
        case .gemini:
            "Gemini models via Google's OpenAI-compatible endpoint."
        case .yunwu:
            "One key, 200+ models (GPT/Claude/Gemini/…). Enter any model ID it supports."
        }
    }

    /// YUNWU proxies arbitrary upstream model IDs, so its catalog is a starting point
    /// rather than a closed set — the Settings UI lets the user type any model ID.
    public var allowsCustomModel: Bool {
        self == .yunwu
    }

    public var defaultModelID: String {
        models.first?.id ?? ""
    }

    public var models: [AIModelOption] {
        switch self {
        case .anthropic:
            return [
                AIModelOption(id: "claude-opus-4-8", name: "Claude Opus 4.8", blurb: "Most capable — best for deep author conversations."),
                AIModelOption(id: "claude-sonnet-5", name: "Claude Sonnet 5", blurb: "Fast and strong — lower-cost everyday choice."),
                AIModelOption(id: "claude-haiku-4-5", name: "Claude Haiku 4.5", blurb: "Fastest and cheapest — quick summaries."),
            ]
        case .openai:
            return [
                AIModelOption(id: "gpt-5", name: "GPT-5", blurb: "OpenAI's most capable model."),
                AIModelOption(id: "gpt-5-mini", name: "GPT-5 mini", blurb: "Smaller, faster, cheaper GPT-5."),
                AIModelOption(id: "gpt-4o", name: "GPT-4o", blurb: "Fast multimodal workhorse."),
                AIModelOption(id: "gpt-4o-mini", name: "GPT-4o mini", blurb: "Low-cost option for light tasks."),
                AIModelOption(id: "o4-mini", name: "o4-mini", blurb: "Reasoning model, cost-efficient."),
            ]
        case .gemini:
            // "-latest" aliases track Google's current recommended Flash/Flash-Lite so a
            // pinned version being retired can't strand us (the old catalog pinned
            // gemini-2.5-flash, which Google deprecated for new keys). Default is Flash-Lite
            // — the quickest and cheapest model on the free tier.
            return [
                AIModelOption(id: "gemini-flash-lite-latest", name: "Gemini Flash-Lite (Latest)", blurb: "Quickest and cheapest — free tier. Recommended."),
                AIModelOption(id: "gemini-flash-latest", name: "Gemini Flash (Latest)", blurb: "More capable, still fast and free-tier friendly."),
                AIModelOption(id: "gemini-2.5-flash-lite", name: "Gemini 2.5 Flash-Lite", blurb: "Pinned stable Flash-Lite version."),
                AIModelOption(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", blurb: "Pinned stable Flash version."),
            ]
        case .yunwu:
            return [
                AIModelOption(id: "gpt-5", name: "GPT-5 (via YUNWU)", blurb: "OpenAI GPT-5 through the relay."),
                AIModelOption(id: "claude-opus-4-8", name: "Claude Opus 4.8 (via YUNWU)", blurb: "Claude through the relay."),
                AIModelOption(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro (via YUNWU)", blurb: "Gemini through the relay."),
                AIModelOption(id: "deepseek-chat", name: "DeepSeek Chat (via YUNWU)", blurb: "DeepSeek through the relay."),
            ]
        }
    }
}
