import SwiftUI

/// Flipbook's visual identity: "candlelight" — warm amber and bronze against deep
/// paper tones, the light of reading by. One family of gradients used consistently
/// across the library canvas, progress indicators, and celebratory accents, so the
/// app reads as one crafted object rather than default chrome.
public enum BrandTokens {
    public static let amber = Color(red: 0.85, green: 0.62, blue: 0.30)
    public static let honeyGlow = Color(red: 0.93, green: 0.76, blue: 0.46)
    public static let bronze = Color(red: 0.56, green: 0.38, blue: 0.19)
    public static let deepBrown = Color(red: 0.20, green: 0.15, blue: 0.11)

    /// The library's ambient canvas — warm paper by day, dim study by night.
    public static func libraryBackground(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.12, blue: 0.11),
                    Color(red: 0.09, green: 0.08, blue: 0.08),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.96, blue: 0.92),
                Color(red: 0.93, green: 0.89, blue: 0.82),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Reading-progress stroke — a slow turn from honey to bronze.
    public static let progressGradient = AngularGradient(
        colors: [honeyGlow, amber, bronze, amber, honeyGlow],
        center: .center,
        startAngle: .degrees(-90),
        endAngle: .degrees(270)
    )

    /// Warm accent gradient for icon-scale flourishes (empty states, onboarding).
    public static let emberGradient = LinearGradient(
        colors: [honeyGlow, bronze],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
