/// Encodes a base theme plus the user's global warmth/brightness adjustments into the
/// single string used as the render-cache theme key. Adjustments ride inside the key so
/// changing a slider naturally invalidates cached page bitmaps — no extra plumbing.
public enum ThemeRenderKey {
    public static func encode(baseID: String, warmth: Double, brightness: Double) -> String {
        guard warmth != 0 || brightness != 0 else { return baseID }
        return "\(baseID)|\(warmth)|\(brightness)"
    }

    /// Resolves a render key back to a theme definition with adjustments merged into
    /// its filter parameters. Plain theme IDs resolve unchanged.
    public static func resolve(_ key: String) -> ThemeDefinition {
        let parts = key.split(separator: "|")
        guard parts.count == 3,
              let warmth = Double(parts[1]),
              let brightness = Double(parts[2])
        else {
            return BuiltInThemes.theme(id: key)
        }

        let base = BuiltInThemes.theme(id: String(parts[0]))
        return ThemeDefinition(
            id: key,
            displayName: base.displayName,
            pageBackground: base.pageBackground,
            chromeText: base.chromeText,
            pdfContentStrategy: base.pdfContentStrategy,
            filterParameters: PDFFilterParameters(
                warmth: base.filterParameters.warmth + warmth,
                brightness: base.filterParameters.brightness + brightness,
                strength: base.filterParameters.strength
            ),
            isDark: base.isDark
        )
    }
}
