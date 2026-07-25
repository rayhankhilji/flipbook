import SwiftUI

/// Flipbook's visual identity: "cream study" — soft cream paper and warm earth tones by day,
/// a chocolate-mocha study at night. One family of tints used consistently across the library
/// canvas, cards, and accents, so the app reads as one crafted object rather than default
/// chrome. Deliberately monochrome-warm: no pastel salad, the accent does the talking.
public enum BrandTokens {
    public static let sage = ColorTokens.sage
    public static let khaki = ColorTokens.khaki
    public static let cream = ColorTokens.cream
    public static let slate = ColorTokens.slate
    public static let espresso = ColorTokens.espresso

    /// A slightly deeper sage for tinted accents that need to read against cream.
    public static let sageAccent = ColorTokens.dynamic(
        light: (0.60, 0.71, 0.60), dark: (0.50, 0.60, 0.50)
    )
    /// Warm near-black ink for text on tiles in light mode, warm cream in dark (never gray).
    public static let deepInk = ColorTokens.ink

    // Bento-card tints — one cohesive cream/mocha family, stepped subtly so cards read as
    // siblings, not a color wheel. `deepInk` text stays readable on every step.
    public static let tileCream = ColorTokens.dynamic(
        light: (0.949, 0.910, 0.839), dark: (0.212, 0.173, 0.141)
    )
    public static let tileLatte = ColorTokens.dynamic(
        light: (0.929, 0.882, 0.800), dark: (0.235, 0.192, 0.157)
    )
    public static let tileToast = ColorTokens.dynamic(
        light: (0.906, 0.851, 0.757), dark: (0.255, 0.208, 0.169)
    )

    // Legacy tile names — now aliases into the cream/mocha family so old call sites stay warm.
    public static let tileSage = tileLatte
    public static let tileKhaki = tileToast
    public static let tileClay = tileToast
    public static let tileSlate = tileLatte

    /// The library's ambient canvas — warm cream by day, dim mocha study by night.
    /// (Tokens are dynamic, so one gradient serves both appearances.)
    public static func libraryBackground(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [ColorTokens.canvas, ColorTokens.canvasDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Reading-progress stroke — a slow turn through the earth tones.
    public static let progressGradient = AngularGradient(
        colors: [sage, khaki, espresso, khaki, sage],
        center: .center,
        startAngle: .degrees(-90),
        endAngle: .degrees(270)
    )

    /// Warm accent gradient for icon-scale flourishes (empty states, placeholder covers).
    public static let emberGradient = LinearGradient(
        colors: [khaki, espresso],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
