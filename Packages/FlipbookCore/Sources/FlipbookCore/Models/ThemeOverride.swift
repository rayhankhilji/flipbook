import Foundation
import SwiftData

/// A user's tweak to a built-in theme (warmth/brightness offset). Built-in themes
/// themselves are static values in `BuiltInThemes`, not database rows.
@Model
public final class ThemeOverride {
    @Attribute(.unique) public var id: UUID
    public var baseThemeID: String
    public var warmthAdjustment: Double
    public var brightnessAdjustment: Double
    public var customName: String?

    public init(
        id: UUID = UUID(),
        baseThemeID: String,
        warmthAdjustment: Double = 0,
        brightnessAdjustment: Double = 0,
        customName: String? = nil
    ) {
        self.id = id
        self.baseThemeID = baseThemeID
        self.warmthAdjustment = warmthAdjustment
        self.brightnessAdjustment = brightnessAdjustment
        self.customName = customName
    }
}
