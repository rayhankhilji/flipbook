import SwiftUI

/// Thin reading-progress ring overlaid on library book covers and shown in the reader toolbar.
public struct ProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat

    public init(progress: Double, lineWidth: CGFloat = 2.5) {
        self.progress = min(max(progress, 0), 1)
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(ColorTokens.chromeSecondaryText.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(BrandTokens.progressGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(AnimationTokens.standard, value: progress)
        }
    }
}
