import SwiftUI

/// Theme-independent chrome colors — adapt automatically to light/dark via semantic system colors.
public enum ColorTokens {
    public static let chromeBackground = Color(nsColor: .windowBackgroundColor)
    public static let chromeSecondaryBackground = Color(nsColor: .underPageBackgroundColor)
    public static let chromeText = Color(nsColor: .labelColor)
    public static let chromeSecondaryText = Color(nsColor: .secondaryLabelColor)
    public static let chromeSeparator = Color(nsColor: .separatorColor)

    /// Named accent colors offered in Settings > Appearance.
    public static let accentOptions: [AccentOption] = [
        AccentOption(id: "graphite", name: "Graphite", color: Color(red: 0.29, green: 0.31, blue: 0.34)),
        AccentOption(id: "amber", name: "Amber", color: Color(red: 0.78, green: 0.53, blue: 0.20)),
        AccentOption(id: "forest", name: "Forest", color: Color(red: 0.24, green: 0.42, blue: 0.31)),
        AccentOption(id: "clay", name: "Clay", color: Color(red: 0.70, green: 0.38, blue: 0.30)),
        AccentOption(id: "indigo", name: "Indigo", color: Color(red: 0.33, green: 0.35, blue: 0.62)),
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
