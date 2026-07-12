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
