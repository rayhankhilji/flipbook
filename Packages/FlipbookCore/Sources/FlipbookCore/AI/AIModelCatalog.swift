import Foundation

/// The Claude models Flipbook offers in Settings. Kept deliberately small — the reader
/// only needs a capable default plus a faster/cheaper option for lighter tasks. IDs are
/// the exact Anthropic model strings; do not append date suffixes.
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

public enum AIModelCatalog {
    /// Anthropic's most capable widely available model — the right default for the
    /// author-persona conversations, which reward depth over raw speed.
    public static let defaultModelID = "claude-opus-4-8"

    public static let all: [AIModelOption] = [
        AIModelOption(
            id: "claude-opus-4-8",
            name: "Claude Opus 4.8",
            blurb: "Most capable — best for deep author conversations and analysis."
        ),
        AIModelOption(
            id: "claude-sonnet-5",
            name: "Claude Sonnet 5",
            blurb: "Fast and strong — a lighter, lower-cost everyday choice."
        ),
        AIModelOption(
            id: "claude-haiku-4-5",
            name: "Claude Haiku 4.5",
            blurb: "Fastest and cheapest — good for quick page summaries."
        ),
    ]

    public static func option(for id: String) -> AIModelOption {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}
