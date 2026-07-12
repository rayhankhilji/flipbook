import SwiftUI

/// A translucent panel background for chrome (sidebars, popovers, cards). On macOS 26+
/// it uses the system Liquid Glass material; older systems fall back to a blurred
/// `.regularMaterial` so the app still builds and reads correctly.
public struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = SpacingTokens.cornerRadiusMedium) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(
                    shape.strokeBorder(ColorTokens.chromeSeparator.opacity(0.4), lineWidth: 0.5)
                )
        }
    }
}

public extension View {
    func glassPanel(cornerRadius: CGFloat = SpacingTokens.cornerRadiusMedium) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}
