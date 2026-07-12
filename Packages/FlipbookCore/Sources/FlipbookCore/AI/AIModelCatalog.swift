import Foundation

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

/// Thin helpers over `AIProvider`'s per-provider catalogs. Model lists live on
/// `AIProvider` so each backend owns its own set; this just exposes lookups.
public enum AIModelCatalog {
    /// The overall default when nothing is configured yet — Anthropic's flagship.
    public static let defaultModelID = AIProvider.anthropic.defaultModelID

    /// Finds a model's display metadata across every provider (falls back to the raw id).
    public static func option(for id: String) -> AIModelOption {
        for provider in AIProvider.allCases {
            if let match = provider.models.first(where: { $0.id == id }) {
                return match
            }
        }
        return AIModelOption(id: id, name: id, blurb: "")
    }
}
