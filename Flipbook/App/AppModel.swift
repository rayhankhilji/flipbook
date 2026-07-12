import FlipbookCore
import FlipbookDesignSystem
import Observation
import SwiftData
import SwiftUI

/// Root app-wide state — created once in `FlipbookApp`, injected via `.environment`.
/// Per-window reading state lives in `ReadingSession` instead (see Features/Reader),
/// not here, since each window can have a different book open.
@Observable
@MainActor
final class AppModel {
    let modelContext: ModelContext

    private(set) var settings: AppSettings

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.settings = AppModel.fetchSettings(in: modelContext)
    }

    /// The active theme with the user's warmth/brightness adjustments merged in.
    /// Its `id` is a full render key, so passing it to the renderer automatically
    /// caches adjusted pages separately from unadjusted ones.
    var currentTheme: ThemeDefinition {
        ThemeRenderKey.resolve(ThemeRenderKey.encode(
            baseID: settings.selectedThemeID,
            warmth: settings.warmthAdjustment,
            brightness: settings.brightnessAdjustment
        ))
    }

    var accentColor: Color {
        ColorTokens.accent(for: settings.accentColorID)
    }

    /// Nil means "follow the system" — the two explicit cases pin the window's scheme.
    var preferredColorScheme: ColorScheme? {
        switch settings.appAppearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func setAppearance(_ appearance: AppAppearance) {
        settings.appAppearance = appearance
        save()
    }

    /// Animation tokens scaled by the user's Settings > Display speed preference.
    func animation(_ base: AnimationKind) -> Animation {
        switch base {
        case .standard: AnimationTokens.standard(speedMultiplier: settings.animationSpeed)
        case .quick: AnimationTokens.quick(speedMultiplier: settings.animationSpeed)
        case .pageTurn: AnimationTokens.pageTurn(speedMultiplier: settings.animationSpeed)
        }
    }

    enum AnimationKind {
        case standard, quick, pageTurn
    }

    func setTheme(id: String) {
        settings.selectedThemeID = id
        save()
    }

    func save() {
        try? modelContext.save()
    }

    private static func fetchSettings(in context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let created = AppSettings()
        context.insert(created)
        try? context.save()
        return created
    }
}
