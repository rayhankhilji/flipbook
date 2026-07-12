import CoreGraphics
import Foundation

/// A plain sRGB color value with no SwiftUI dependency, so it can drive both
/// UI-layer color tokens (via an extension in FlipbookDesignSystem) and the
/// Core Image filter math in `ThemeCompositor`.
public struct FlipbookRGBColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Convenience initializer from a 6-digit hex string, e.g. "F6F1E7".
    public init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&value)
        self.red = Double((value & 0xFF0000) >> 16) / 255.0
        self.green = Double((value & 0x00FF00) >> 8) / 255.0
        self.blue = Double(value & 0x0000FF) / 255.0
    }

    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: 1.0)
    }

    /// Relative luminance per WCAG, used for contrast-ratio checks between theme token pairs.
    public var relativeLuminance: Double {
        func linearize(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
    }

    /// WCAG contrast ratio (1...21) between this color and another.
    public func contrastRatio(with other: FlipbookRGBColor) -> Double {
        let l1 = relativeLuminance
        let l2 = other.relativeLuminance
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
