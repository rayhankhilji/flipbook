import AppKit
import SwiftUI

/// Theme-independent chrome colors. The whole palette is *dynamic*: every token resolves to
/// its warm-cream value in light mode and a chocolate-mocha counterpart in dark mode, so the
/// app is one designed object in both appearances — never system gray.
public enum ColorTokens {
    public static let chromeBackground = Color(nsColor: .windowBackgroundColor)
    public static let chromeSecondaryBackground = Color(nsColor: .underPageBackgroundColor)
    public static let chromeText = Color(nsColor: .labelColor)
    public static let chromeSecondaryText = Color(nsColor: .secondaryLabelColor)
    public static let chromeSeparator = Color(nsColor: .separatorColor)

    /// A color that resolves per-appearance: cream in light, mocha in dark.
    static func dynamic(
        light: (r: Double, g: Double, b: Double),
        dark: (r: Double, g: Double, b: Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        })
    }

    // MARK: - Flipbook palette
    // The app's identity: soft cream paper and warm earth tones by day; the same room with
    // the lights down — chocolate, mocha, latte — in dark mode.

    /// Sage green — quiet supporting tint (kept out of tiles/stat cards by design).
    public static let sage = dynamic(light: (0.671, 0.769, 0.671), dark: (0.545, 0.639, 0.545))
    /// Warm khaki / tan.
    public static let khaki = dynamic(light: (0.639, 0.569, 0.443), dark: (0.722, 0.643, 0.506))
    /// Cream — the paper surface.
    public static let cream = dynamic(light: (0.863, 0.788, 0.714), dark: (0.376, 0.310, 0.259))
    /// Muted slate-sage.
    public static let slate = dynamic(light: (0.447, 0.490, 0.443), dark: (0.588, 0.631, 0.584))
    /// Espresso — text-strength accent: deep brown on cream, warm latte on mocha.
    public static let espresso = dynamic(light: (0.427, 0.298, 0.239), dark: (0.867, 0.761, 0.655))

    /// The app's primary brand accent (buttons, selection, focus rings) — dark accent in
    /// light mode, light accent in dark mode.
    public static let brandPrimary = espresso

    // MARK: - Surfaces

    /// Main canvas — dashboard / library background base.
    public static let canvas = dynamic(light: (0.960, 0.936, 0.894), dark: (0.153, 0.122, 0.100))
    /// A hair deeper for the bottom of the canvas gradient.
    public static let canvasDeep = dynamic(light: (0.894, 0.845, 0.773), dark: (0.110, 0.087, 0.071))
    /// The left sidebar panel — warm parchment / darker mocha shelf.
    public static let sidebarSurface = dynamic(light: (0.902, 0.859, 0.792), dark: (0.184, 0.147, 0.120))
    /// Slightly deeper parchment for the sidebar footer bar.
    public static let sidebarFooter = dynamic(light: (0.867, 0.816, 0.741), dark: (0.161, 0.128, 0.104))
    /// Warm near-black ink on cream; warm cream ink on mocha. Never system gray.
    public static let ink = dynamic(light: (0.204, 0.149, 0.118), dark: (0.941, 0.902, 0.851))
    public static let inkSecondary = dynamic(light: (0.404, 0.337, 0.282), dark: (0.753, 0.682, 0.604))
    /// Hairline divider tuned for cream/mocha, not system separator gray.
    public static let creamHairline = dynamic(light: (0.678, 0.612, 0.522), dark: (0.357, 0.298, 0.247))

    /// Named accent colors offered in Settings > Appearance. Each is dynamic — a dark ink in
    /// light mode, a lifted latte version of itself in dark mode.
    public static let accentOptions: [AccentOption] = [
        AccentOption(id: "espresso", name: "Espresso", color: espresso),
        AccentOption(id: "sage", name: "Sage",
                     color: dynamic(light: (0.478, 0.588, 0.478), dark: (0.686, 0.776, 0.686))),
        AccentOption(id: "slate", name: "Slate",
                     color: dynamic(light: (0.447, 0.490, 0.443), dark: (0.700, 0.741, 0.694))),
        AccentOption(id: "khaki", name: "Khaki",
                     color: dynamic(light: (0.580, 0.502, 0.373), dark: (0.784, 0.706, 0.573))),
    ]

    public static func accent(for id: String) -> Color {
        accentOptions.first(where: { $0.id == id })?.color ?? accentOptions[0].color
    }
}

public struct AccentOption: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let color: Color

    public init(id: String, name: String, color: Color) {
        self.id = id
        self.name = name
        self.color = color
    }
}
