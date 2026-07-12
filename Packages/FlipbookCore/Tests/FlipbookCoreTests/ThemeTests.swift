import Testing

@testable import FlipbookCore

@Suite struct ThemeTests {
    @Test func hexParsingRoundTrips() {
        let color = FlipbookRGBColor(hex: "F6F1E7")
        #expect(abs(color.red - 246.0 / 255.0) < 0.001)
        #expect(abs(color.green - 241.0 / 255.0) < 0.001)
        #expect(abs(color.blue - 231.0 / 255.0) < 0.001)
    }

    /// Every built-in theme's chrome text must meet WCAG AA contrast (4.5:1) against
    /// its page background — checked here rather than eyeballed.
    @Test(arguments: BuiltInThemes.all)
    func themeMeetsContrastRequirement(theme: ThemeDefinition) {
        let ratio = theme.chromeText.contrastRatio(with: theme.pageBackground)
        #expect(ratio >= 4.5, "\(theme.displayName) contrast ratio \(ratio) below 4.5:1")
    }

    @Test func unknownThemeIDFallsBackToDefault() {
        #expect(BuiltInThemes.theme(id: "nonexistent").id == BuiltInThemes.warmPaper.id)
    }

    @Test func darkThemesUseInvertStrategies() {
        for theme in BuiltInThemes.all where theme.isDark {
            #expect(theme.pdfContentStrategy != .tintOnly, "\(theme.displayName) is dark but tint-only")
        }
    }
}
