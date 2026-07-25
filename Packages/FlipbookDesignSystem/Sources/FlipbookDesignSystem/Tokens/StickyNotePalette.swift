import SwiftUI

/// Sticky-note paper colors — soft, warm tones that sit happily on a page or in the margin.
public enum StickyNotePalette {
    public struct Entry: Identifiable, Sendable {
        public let id: String
        public let name: String
        /// The note's paper fill.
        public let paper: Color
        /// A slightly deeper edge/tab color for the collapsed tab and shadow line.
        public let edge: Color
    }

    public static let all: [Entry] = [
        Entry(id: "lemon", name: "Lemon",
              paper: Color(red: 0.98, green: 0.90, blue: 0.55), edge: Color(red: 0.85, green: 0.72, blue: 0.32)),
        Entry(id: "sage", name: "Sage",
              paper: Color(red: 0.78, green: 0.86, blue: 0.74), edge: Color(red: 0.55, green: 0.66, blue: 0.52)),
        Entry(id: "peach", name: "Peach",
              paper: Color(red: 0.98, green: 0.80, blue: 0.68), edge: Color(red: 0.86, green: 0.60, blue: 0.47)),
        Entry(id: "sky", name: "Sky",
              paper: Color(red: 0.75, green: 0.85, blue: 0.93), edge: Color(red: 0.52, green: 0.68, blue: 0.82)),
        Entry(id: "clay", name: "Clay",
              paper: Color(red: 0.86, green: 0.75, blue: 0.66), edge: Color(red: 0.66, green: 0.52, blue: 0.43)),
    ]

    public static func entry(for id: String) -> Entry {
        all.first(where: { $0.id == id }) ?? all[0]
    }

    public static func paper(for id: String) -> Color { entry(for: id).paper }
    public static func edge(for id: String) -> Color { entry(for: id).edge }
}
