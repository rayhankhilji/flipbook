import FlipbookCore
import SwiftUI

/// SwiftUI-facing extension over `FlipbookCore.FlipbookRGBColor` — kept out of Core so that
/// package stays free of a SwiftUI dependency.
public extension FlipbookRGBColor {
    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}
