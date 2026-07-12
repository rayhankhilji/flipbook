/// A built-in or user-defined reading theme. Pure data — no SwiftUI/PDFKit dependency —
/// so it can be shared by the design system (for chrome colors) and `ThemeCompositor`
/// (for PDF pixel filtering) without either pulling in the other's framework.
public struct ThemeDefinition: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String

    /// "Paper" color shown behind/around the page and used to tint chrome.
    public let pageBackground: FlipbookRGBColor
    /// Chrome text/icon color when the reading UI overlays this theme.
    public let chromeText: FlipbookRGBColor

    public let pdfContentStrategy: PDFContentStrategy
    public let filterParameters: PDFFilterParameters
    public let isDark: Bool

    public init(
        id: String,
        displayName: String,
        pageBackground: FlipbookRGBColor,
        chromeText: FlipbookRGBColor,
        pdfContentStrategy: PDFContentStrategy,
        filterParameters: PDFFilterParameters,
        isDark: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.pageBackground = pageBackground
        self.chromeText = chromeText
        self.pdfContentStrategy = pdfContentStrategy
        self.filterParameters = filterParameters
        self.isDark = isDark
    }
}
