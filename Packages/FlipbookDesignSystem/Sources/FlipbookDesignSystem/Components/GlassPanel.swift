import SwiftUI

/// A tasteful translucent panel background for sidebars/toolbars — subtle blur, never opaque.
public struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = SpacingTokens.cornerRadiusMedium) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ColorTokens.chromeSeparator.opacity(0.4), lineWidth: 0.5)
            )
    }
}

public extension View {
    func glassPanel(cornerRadius: CGFloat = SpacingTokens.cornerRadiusMedium) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}
