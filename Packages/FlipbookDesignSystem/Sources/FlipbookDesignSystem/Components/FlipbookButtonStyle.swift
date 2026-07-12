import SwiftUI

/// A calm, understated primary button style — subtle press feedback, no flashy motion.
public struct FlipbookButtonStyle: ButtonStyle {
    var prominent: Bool

    public init(prominent: Bool = false) {
        self.prominent = prominent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypographyTokens.callout.weight(.medium))
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.sm)
            .background(
                RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusSmall, style: .continuous)
                    .fill(prominent ? ColorTokens.accent(for: "graphite") : Color.clear)
                    .opacity(prominent ? (configuration.isPressed ? 0.75 : 1.0) : (configuration.isPressed ? 0.08 : 0.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(ColorTokens.chromeSeparator.opacity(prominent ? 0 : 0.5), lineWidth: 0.75)
            )
            .foregroundStyle(prominent ? .white : ColorTokens.chromeText)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(AnimationTokens.quick, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == FlipbookButtonStyle {
    static var flipbook: FlipbookButtonStyle { FlipbookButtonStyle() }
    static func flipbook(prominent: Bool) -> FlipbookButtonStyle { FlipbookButtonStyle(prominent: prominent) }
}
