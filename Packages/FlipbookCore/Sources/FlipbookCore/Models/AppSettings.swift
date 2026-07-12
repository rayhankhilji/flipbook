import Foundation
import SwiftData

/// Singleton settings row. `ModelContainerFactory` enforces exactly one row exists.
@Model
public final class AppSettings {
    /// Always 0 — the singleton-row key.
    @Attribute(.unique) public var id: Int

    // Reading
    public var selectedThemeID: String
    public var defaultNavigationMode: NavigationMode
    public var pageMarginsEnabled: Bool
    public var fullscreenAutoHideToolbar: Bool
    /// Global warmth/brightness offsets applied on top of the active theme's own
    /// filter parameters (see `ThemeRenderKey`).
    public var warmthAdjustment: Double = 0
    public var brightnessAdjustment: Double = 0

    // Reflow mode typography ("serif", "sans", "rounded", "mono")
    public var reflowFontID: String = "serif"
    public var reflowTextSize: Double = 18

    // Display
    public var animationSpeed: Double
    public var interfaceDensity: InterfaceDensity
    public var defaultZoom: Double

    // Navigation
    public var gestureSwipeToTurnPage: Bool
    public var gesturePinchToZoom: Bool

    // Appearance
    public var accentColorID: String
    public var uiTransparencyEnabled: Bool
    public var sidebarVisibleByDefault: Bool

    public init(
        id: Int = 0,
        selectedThemeID: String = "warmPaper",
        defaultNavigationMode: NavigationMode = .pageTurn,
        pageMarginsEnabled: Bool = true,
        fullscreenAutoHideToolbar: Bool = true,
        animationSpeed: Double = 1.0,
        interfaceDensity: InterfaceDensity = .comfortable,
        defaultZoom: Double = 1.0,
        gestureSwipeToTurnPage: Bool = true,
        gesturePinchToZoom: Bool = true,
        accentColorID: String = "graphite",
        uiTransparencyEnabled: Bool = true,
        sidebarVisibleByDefault: Bool = true
    ) {
        self.id = id
        self.selectedThemeID = selectedThemeID
        self.defaultNavigationMode = defaultNavigationMode
        self.pageMarginsEnabled = pageMarginsEnabled
        self.fullscreenAutoHideToolbar = fullscreenAutoHideToolbar
        self.animationSpeed = animationSpeed
        self.interfaceDensity = interfaceDensity
        self.defaultZoom = defaultZoom
        self.gestureSwipeToTurnPage = gestureSwipeToTurnPage
        self.gesturePinchToZoom = gesturePinchToZoom
        self.accentColorID = accentColorID
        self.uiTransparencyEnabled = uiTransparencyEnabled
        self.sidebarVisibleByDefault = sidebarVisibleByDefault
    }
}
