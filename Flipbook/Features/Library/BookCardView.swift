import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// A book on the library shelf: cover with stacked page-edge depth behind it, a warm
/// progress ring, and a gentle lift on hover — an object you want to pick up.
struct BookCardView: View {
    let book: Book
    let isSelected: Bool

    @State private var isHovered = false

    private var progressFraction: Double {
        guard book.pageCount > 0, let progress = book.progress else { return 0 }
        return Double(progress.currentPageIndex) / Double(book.pageCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            ZStack(alignment: .bottomTrailing) {
                bookBody
                statusBadge
            }
            .scaleEffect(isHovered || isSelected ? 1.03 : 1.0)
            .offset(y: isHovered ? -4 : 0)
            .animation(AnimationTokens.quick, value: isHovered)
            .animation(AnimationTokens.quick, value: isSelected)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(TypographyTokens.bookTitle)
                    .foregroundStyle(ColorTokens.chromeText)
                    .lineLimit(2)

                HStack(spacing: SpacingTokens.xs) {
                    if let author = book.authorHint, !author.isEmpty {
                        Text(author)
                            .lineLimit(1)
                    }
                    if progressFraction > 0 {
                        if book.authorHint?.isEmpty == false {
                            Text("·")
                        }
                        Text("\(Int(progressFraction * 100))%")
                            .monospacedDigit()
                    }
                }
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.chromeSecondaryText)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(book.title), \(Int(progressFraction * 100)) percent read"))
        .accessibilityAddTraits(.isButton)
    }

    /// Cover with two offset sheets behind it, so the card reads as a bound block of
    /// pages rather than a flat image.
    private var bookBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusMedium, style: .continuous)
                .fill(Color(white: 0.98))
                .offset(x: 5, y: 5)
                .opacity(0.55)
            RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusMedium, style: .continuous)
                .fill(Color(white: 0.94))
                .offset(x: 2.5, y: 2.5)
                .opacity(0.8)

            coverImage
                .aspectRatio(0.72, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusMedium, style: .continuous))
                .overlay(spineHighlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(.black.opacity(0.12), lineWidth: 0.75)
                )
        }
        .aspectRatio(0.72, contentMode: .fit)
        .shadow(
            color: .black.opacity(isHovered || isSelected ? 0.32 : 0.2),
            radius: isHovered || isSelected ? 16 : 9,
            y: isHovered || isSelected ? 10 : 5
        )
    }

    /// A faint vertical sheen near the leading edge suggests the cover's curl at the spine.
    private var spineHighlight: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.18), .black.opacity(0.02), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 10)
            Spacer(minLength: 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusMedium, style: .continuous))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if book.isMissing {
            Image(systemName: "questionmark.folder.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .padding(SpacingTokens.sm)
        } else if progressFraction > 0 {
            ProgressRing(progress: progressFraction)
                .frame(width: 22, height: 22)
                .padding(SpacingTokens.xs)
                .background(.regularMaterial, in: Circle())
                .padding(SpacingTokens.sm)
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let data = book.coverImageData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
        } else {
            RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusMedium, style: .continuous)
                .fill(BrandTokens.emberGradient)
                .overlay(
                    Image(systemName: "book.closed.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.85))
                )
        }
    }
}
