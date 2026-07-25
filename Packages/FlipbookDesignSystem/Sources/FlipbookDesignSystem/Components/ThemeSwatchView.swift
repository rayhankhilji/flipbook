import FlipbookCore
import SwiftUI

/// A small tappable swatch representing a reading theme — used in the theme quick-switcher
/// popover and the Settings > Reading theme grid.
public struct ThemeSwatchView: View {
    let theme: ThemeDefinition
    let isSelected: Bool
    let action: () -> Void

    public init(theme: ThemeDefinition, isSelected: Bool, action: @escaping () -> Void) {
        self.theme = theme
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: SpacingTokens.sm) {
                Circle()
                    .fill(theme.pageBackground.color)
                    .overlay(
                        Circle().strokeBorder(theme.chromeText.color.opacity(0.25), lineWidth: 1)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(ColorTokens.brandPrimary, lineWidth: isSelected ? 2.5 : 0)
                            .padding(-3)
                    )
                    .frame(width: 32, height: 32)

                Text(theme.displayName)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(theme.displayName))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
