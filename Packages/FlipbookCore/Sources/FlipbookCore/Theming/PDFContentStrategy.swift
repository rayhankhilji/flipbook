/// How `ThemeCompositor` should treat rasterized PDF page pixels for a given theme.
///
/// PDF page content is fixed raster/vector content on a white background — it can't be
/// restyled generically like SwiftUI chrome, so each theme picks one of these strategies.
public enum PDFContentStrategy: String, Sendable, Codable {
    /// Gentle warm color-multiply overlay; never distorts photos. Used by light/paper themes.
    case tintOnly

    /// Lightness-preserving-hue invert, so black-on-white text becomes light-on-dark without
    /// turning photos into ugly color negatives. Used by dark themes on text-heavy pages.
    case smartInvert

    /// Runs a cheap per-page heuristic (histogram/edge density) to detect photo-heavy vs.
    /// text-heavy pages, applying `smartInvert`-like treatment to text pages and a gentler
    /// dim-only treatment to photo/scan-heavy pages so images aren't color-negated.
    case imageAwareInvert
}

/// Parameters fed into the Core Image filter chain in `ThemeCompositor`.
public struct PDFFilterParameters: Sendable, Equatable, Codable {
    /// Base warmth applied via CITemperatureAndTint, in addition to any user warmth setting.
    public var warmth: Double
    /// Base brightness/exposure adjustment via CIExposureAdjust.
    public var brightness: Double
    /// Strength of the tint/invert blend (0 = no effect, 1 = full effect).
    public var strength: Double

    public init(warmth: Double = 0, brightness: Double = 0, strength: Double = 1.0) {
        self.warmth = warmth
        self.brightness = brightness
        self.strength = strength
    }
}
