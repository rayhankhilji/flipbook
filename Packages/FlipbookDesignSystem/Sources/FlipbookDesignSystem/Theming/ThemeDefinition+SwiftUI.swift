import FlipbookCore
import SwiftUI

public extension ThemeDefinition {
    /// The page ("paper") color as a SwiftUI color.
    var pageColor: Color {
        pageBackground.color
    }

    /// The reading canvas behind/around pages — offset slightly from the paper color
    /// so pages visibly lift off the background: darker for light themes, a touch
    /// lighter for dark themes (where "darker" would be imperceptible).
    var canvasColor: Color {
        if isDark {
            return Color(
                red: min(pageBackground.red + 0.045, 1),
                green: min(pageBackground.green + 0.045, 1),
                blue: min(pageBackground.blue + 0.045, 1)
            )
        }
        return Color(
            red: pageBackground.red * 0.93,
            green: pageBackground.green * 0.93,
            blue: pageBackground.blue * 0.93
        )
    }

    /// Chrome text color for UI overlaying this theme.
    var chromeTextColor: Color {
        chromeText.color
    }
}
