import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// Focus mode's way home. The toolbar is hidden, so a glass pill floats in when the
/// pointer approaches the top of the window — page position, previous/next, and an
/// explicit exit — and melts away when the pointer leaves. Esc always works too.
struct FocusEscapeBar: View {
    let session: ReadingSession
    let pageStep: Int
    let exitFocus: () -> Void

    @State private var isRevealed = false

    var body: some View {
        VStack {
            pill
                .opacity(isRevealed ? 1 : 0)
                .offset(y: isRevealed ? 0 : -12)
                .animation(AnimationTokens.quick, value: isRevealed)
                .padding(.top, SpacingTokens.md)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76, alignment: .top)
        .contentShape(Rectangle())
        .onHover { hovering in
            isRevealed = hovering
        }
        .accessibilityElement(children: .contain)
    }

    private var pill: some View {
        HStack(spacing: SpacingTokens.md) {
            Button {
                session.jump(toPage: session.currentPageIndex - pageStep)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Previous page"))

            Text("\(session.currentPageIndex + 1) of \(session.pageCount)")
                .font(TypographyTokens.caption)
                .monospacedDigit()
                .foregroundStyle(ColorTokens.chromeSecondaryText)

            Button {
                session.jump(toPage: session.currentPageIndex + pageStep)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Next page"))

            Divider().frame(height: 14)

            Button(action: exitFocus) {
                HStack(spacing: SpacingTokens.xs) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                    Text("Exit Focus")
                        .font(TypographyTokens.caption)
                    Text("esc")
                        .font(TypographyTokens.monospaceCaption)
                        .foregroundStyle(ColorTokens.chromeSecondaryText)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Exit focus mode"))
        }
        .padding(.horizontal, SpacingTokens.md)
        .padding(.vertical, SpacingTokens.sm)
        .glassPanel(cornerRadius: 999)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
    }
}
