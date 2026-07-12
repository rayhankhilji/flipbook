import SwiftUI

/// Highlight colors — muted, paper-friendly tones rather than fluorescent marker hues.
public enum HighlightPalette {
    public struct Entry: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let color: Color
    }

    public static let all: [Entry] = [
        Entry(id: "honey", name: "Honey", color: Color(red: 0.95, green: 0.78, blue: 0.35)),
        Entry(id: "sage", name: "Sage", color: Color(red: 0.55, green: 0.72, blue: 0.51)),
        Entry(id: "sky", name: "Sky", color: Color(red: 0.47, green: 0.66, blue: 0.85)),
        Entry(id: "rose", name: "Rose", color: Color(red: 0.89, green: 0.56, blue: 0.62)),
        Entry(id: "lavender", name: "Lavender", color: Color(red: 0.68, green: 0.58, blue: 0.85)),
    ]

    public static func color(for id: String) -> Color {
        all.first(where: { $0.id == id })?.color ?? all[0].color
    }

    /// Translucent fill used when drawing the highlight over page content.
    public static func overlayColor(for id: String, isDarkTheme: Bool) -> Color {
        color(for: id).opacity(isDarkTheme ? 0.42 : 0.35)
    }
}
