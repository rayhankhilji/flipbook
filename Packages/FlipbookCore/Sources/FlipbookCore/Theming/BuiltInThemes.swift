/// The built-in reading theme catalog. Deliberately avoids pure white/black —
/// every palette is tuned to be comfortable for long reading sessions.
public enum BuiltInThemes {
    public static let warmPaper = ThemeDefinition(
        id: "warmPaper",
        displayName: "Warm Paper",
        pageBackground: FlipbookRGBColor(hex: "F6F1E7"),
        chromeText: FlipbookRGBColor(hex: "2B2723"),
        pdfContentStrategy: .tintOnly,
        filterParameters: PDFFilterParameters(warmth: 0.15, brightness: 0, strength: 0.5),
        isDark: false
    )

    public static let eggshell = ThemeDefinition(
        id: "eggshell",
        displayName: "Eggshell",
        pageBackground: FlipbookRGBColor(hex: "F3EEE4"),
        chromeText: FlipbookRGBColor(hex: "2A2622"),
        pdfContentStrategy: .tintOnly,
        filterParameters: PDFFilterParameters(warmth: 0.10, brightness: 0, strength: 0.4),
        isDark: false
    )

    public static let cream = ThemeDefinition(
        id: "cream",
        displayName: "Cream",
        pageBackground: FlipbookRGBColor(hex: "FBF3DC"),
        chromeText: FlipbookRGBColor(hex: "332C1E"),
        pdfContentStrategy: .tintOnly,
        filterParameters: PDFFilterParameters(warmth: 0.20, brightness: 0.02, strength: 0.5),
        isDark: false
    )

    public static let beige = ThemeDefinition(
        id: "beige",
        displayName: "Beige",
        pageBackground: FlipbookRGBColor(hex: "EFE4CF"),
        chromeText: FlipbookRGBColor(hex: "302A20"),
        pdfContentStrategy: .tintOnly,
        filterParameters: PDFFilterParameters(warmth: 0.18, brightness: 0, strength: 0.5),
        isDark: false
    )

    public static let sepia = ThemeDefinition(
        id: "sepia",
        displayName: "Sepia",
        pageBackground: FlipbookRGBColor(hex: "E8D8B8"),
        chromeText: FlipbookRGBColor(hex: "4A3826"),
        pdfContentStrategy: .tintOnly,
        filterParameters: PDFFilterParameters(warmth: 0.30, brightness: -0.02, strength: 0.6),
        isDark: false
    )

    public static let original = ThemeDefinition(
        id: "original",
        displayName: "Original",
        pageBackground: FlipbookRGBColor(hex: "FDFDFC"),
        chromeText: FlipbookRGBColor(hex: "1C1C1E"),
        pdfContentStrategy: .tintOnly,
        filterParameters: PDFFilterParameters(warmth: 0, brightness: 0, strength: 0),
        isDark: false
    )

    public static let darkGrey = ThemeDefinition(
        id: "darkGrey",
        displayName: "Dark Grey",
        pageBackground: FlipbookRGBColor(hex: "26262A"),
        chromeText: FlipbookRGBColor(hex: "E7E5E1"),
        pdfContentStrategy: .imageAwareInvert,
        filterParameters: PDFFilterParameters(warmth: -0.05, brightness: 0, strength: 0.85),
        isDark: true
    )

    public static let midnight = ThemeDefinition(
        id: "midnight",
        displayName: "Midnight",
        pageBackground: FlipbookRGBColor(hex: "151726"),
        chromeText: FlipbookRGBColor(hex: "DCE0EC"),
        pdfContentStrategy: .smartInvert,
        filterParameters: PDFFilterParameters(warmth: -0.10, brightness: -0.02, strength: 0.9),
        isDark: true
    )

    public static let trueBlack = ThemeDefinition(
        id: "trueBlack",
        displayName: "True Black",
        pageBackground: FlipbookRGBColor(hex: "0A0A0B"),
        chromeText: FlipbookRGBColor(hex: "EDEDED"),
        pdfContentStrategy: .smartInvert,
        filterParameters: PDFFilterParameters(warmth: 0, brightness: -0.03, strength: 1.0),
        isDark: true
    )

    /// All built-in themes, in display order.
    public static let all: [ThemeDefinition] = [
        warmPaper, eggshell, cream, beige, sepia, original, darkGrey, midnight, trueBlack,
    ]

    public static func theme(id: String) -> ThemeDefinition {
        all.first(where: { $0.id == id }) ?? warmPaper
    }
}
