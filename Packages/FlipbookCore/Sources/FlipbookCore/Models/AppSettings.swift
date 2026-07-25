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

    // Window
    /// Whether opening a book takes the window full screen automatically. When off, the
    /// window keeps its compact shape but becomes freely resizable while reading.
    /// Defaulted so SwiftData lightweight migration adds it to existing stores.
    public var openBookFullScreen: Bool = true

    // Night & comfort (all defaulted for lightweight migration)
    /// Automatically switch the reading theme to `nightThemeID` during night hours
    /// (20:00–07:00), and back in the morning.
    public var nightModeEnabled: Bool = false
    /// The dark reading theme night mode switches to.
    public var nightThemeID: String = "midnight"
    /// Keep the Mac's display awake while a book is open.
    public var keepAwakeWhileReading: Bool = false
    /// Daily reading goal in minutes; 0 = no goal.
    public var dailyGoalMinutes: Int = 0

    // Appearance
    public var accentColorID: String
    public var uiTransparencyEnabled: Bool
    public var sidebarVisibleByDefault: Bool
    /// Chrome light/dark preference. Defaulted so SwiftData lightweight migration
    /// adds it to existing stores without a manual migration plan.
    public var appAppearanceRaw: String = AppAppearance.system.rawValue

    // AI (bring-your-own-key). API keys are NOT stored here — they live per-provider in the
    // Keychain (`AIKeychain`). SwiftData only holds non-secret preferences. All defaulted so
    // SwiftData lightweight migration adds them without a manual migration plan.
    public var aiEnabled: Bool = false
    public var aiProviderRaw: String = AIProvider.anthropic.rawValue
    public var aiModelID: String = AIProvider.anthropic.defaultModelID

    // AI personalization — folded into the system prompt on every conversation.
    public var aiAssistantName: String = ""
    public var aiCustomInstructions: String = ""
    public var aiResponseStyleRaw: String = AIResponseStyle.balanced.rawValue
    /// Whether messages are automatically grounded with the current page's text. Off means
    /// the assistant only knows the book's title and author.
    public var aiAutoContextEnabled: Bool = true

    public var aiProvider: AIProvider {
        get { AIProvider(rawValue: aiProviderRaw) ?? .anthropic }
        set { aiProviderRaw = newValue.rawValue }
    }

    public var aiResponseStyle: AIResponseStyle {
        get { AIResponseStyle(rawValue: aiResponseStyleRaw) ?? .balanced }
        set { aiResponseStyleRaw = newValue.rawValue }
    }

    public var appAppearance: AppAppearance {
        get { AppAppearance(rawValue: appAppearanceRaw) ?? .system }
        set { appAppearanceRaw = newValue.rawValue }
    }

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
        accentColorID: String = "espresso",
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
