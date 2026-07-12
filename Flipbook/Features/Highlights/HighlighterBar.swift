import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// The floating control bar shown while the highlighter tool is on: pick a color and
/// style, then drag across the page to mark. Tapping an existing mark erases it. Mutates
/// the session's ephemeral highlighter state directly.
struct HighlighterBar: View {
    let session: ReadingSession
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: SpacingTokens.md) {
            Image(systemName: "highlighter")
                .font(.callout.weight(.semibold))
                .foregroundStyle(HighlightPalette.color(for: session.highlighterColorTag))

            styleToggle

            Divider().frame(height: 18)

            HStack(spacing: SpacingTokens.sm) {
                ForEach(HighlightPalette.all) { entry in
                    swatch(entry)
                }
            }

            Divider().frame(height: 18)

            Text("Draw to mark · tap a mark to erase")
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.chromeSecondaryText)
                .fixedSize()

            Button(action: onDone) {
                Text("Done")
                    .font(TypographyTokens.callout.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, SpacingTokens.lg)
        .padding(.vertical, SpacingTokens.sm)
        .glassPanel(cornerRadius: 999)
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .padding(.bottom, SpacingTokens.xl)
    }

    private var styleToggle: some View {
        HStack(spacing: 2) {
            ForEach(["highlight", "underline"], id: \.self) { style in
                Button {
                    session.highlighterStyle = style
                } label: {
                    Image(systemName: style == "highlight" ? "highlighter" : "pencil.tip")
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(session.highlighterStyle == style ? Color.primary.opacity(0.12) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(style == "highlight" ? "Marker — thick, translucent" : "Pen — thin line")
                .accessibilityLabel(Text(style == "highlight" ? "Marker style" : "Pen style"))
                .accessibilityAddTraits(session.highlighterStyle == style ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func swatch(_ entry: HighlightPalette.Entry) -> some View {
        let selected = session.highlighterColorTag == entry.id
        return Button {
            session.highlighterColorTag = entry.id
        } label: {
            Circle()
                .fill(entry.color)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().strokeBorder(
                        selected ? Color.primary : .white.opacity(0.6),
                        lineWidth: selected ? 2.5 : 1
                    )
                )
                .scaleEffect(selected ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .help(entry.name)
        .accessibilityLabel(Text(entry.name))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .animation(AnimationTokens.quick, value: selected)
    }
}
