/// Reader navigation mode — continuous scroll vs. discrete page-turn.
public enum NavigationMode: String, Sendable, Codable, CaseIterable {
    case pageTurn
    case scroll
}

/// How a `Highlight`'s region was authored.
public enum HighlightKind: String, Sendable, Codable {
    /// Selected via the PDF's text layer (`PDFSelection`); `selectedText` is populated.
    case textSelection
    /// Drawn as a free rectangle over a page with no text layer (scanned PDFs).
    case region
}

/// Settings > Display interface density.
public enum InterfaceDensity: String, Sendable, Codable, CaseIterable {
    case compact
    case comfortable
}

/// Settings → AI personalization tone preset, folded into the assistant's system prompt.
public enum AIResponseStyle: String, Sendable, Codable, CaseIterable {
    case concise
    case balanced
    case thorough

    public var label: String {
        switch self {
        case .concise: "Concise"
        case .balanced: "Balanced"
        case .thorough: "Thorough"
        }
    }

    public var promptFragment: String {
        switch self {
        case .concise: "Keep answers brief — a few sentences or a short list. Expand only if asked."
        case .balanced: "Give answers with enough explanation to be useful, without padding."
        case .thorough: "Give thorough, well-structured answers that explore nuance and cite the text."
        }
    }
}

/// App-wide chrome appearance, independent of the per-book reading theme.
/// `.system` follows macOS; the other two pin the window's color scheme.
public enum AppAppearance: String, Sendable, Codable, CaseIterable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }
}
