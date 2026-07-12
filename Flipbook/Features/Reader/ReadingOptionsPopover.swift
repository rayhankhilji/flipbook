import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// The single "Aa" popover that gathers every reading control — view mode, theme,
/// zoom, typography, focus — in one calm place, in the spirit of Apple Books and
/// Safari Reader. Keeps the toolbar down to a handful of buttons.
struct ReadingOptionsPopover: View {
    @Environment(AppModel.self) private var appModel
    let session: ReadingSession
    let enterFocusMode: () -> Void

    private enum ViewMode: String, CaseIterable, Identifiable {
        case book, scroll, reflow
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            viewModeSection
            Divider()
            themeSection

            if session.reflowMode {
                Divider()
                typographySection
            } else if session.navigationMode == .scroll {
                Divider()
                zoomSection
            }

            Divider()
            focusRow
        }
        .padding(SpacingTokens.md)
        .frame(width: 316)
    }

    // MARK: - View mode

    private var viewModeBinding: Binding<ViewMode> {
        Binding {
            if session.reflowMode { return .reflow }
            return session.navigationMode == .pageTurn ? .book : .scroll
        } set: { mode in
            withAnimation(AnimationTokens.standard) {
                switch mode {
                case .book:
                    session.reflowMode = false
                    session.setNavigationMode(.pageTurn)
                case .scroll:
                    session.reflowMode = false
                    session.setNavigationMode(.scroll)
                case .reflow:
                    session.reflowMode = true
                }
            }
        }
    }

    private var viewModeSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            sectionLabel("View")
            Picker("View Mode", selection: viewModeBinding) {
                Label("Book", systemImage: "book").tag(ViewMode.book)
                Label("Scroll", systemImage: "arrow.up.and.down.text.horizontal").tag(ViewMode.scroll)
                if session.reflowAvailable != false {
                    Label("Reflow", systemImage: "text.justify.leading").tag(ViewMode.reflow)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(viewModeCaption)
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.chromeSecondaryText)
        }
        .task {
            await session.checkReflowAvailability()
        }
    }

    private var viewModeCaption: String {
        if session.reflowMode {
            return "Original text, re-typeset in your font."
        }
        return session.navigationMode == .pageTurn
            ? "Facing pages — swipe or use arrow keys to turn."
            : "Continuous pages — scroll and pinch to zoom."
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            sectionLabel("Theme")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: SpacingTokens.sm)], spacing: SpacingTokens.sm) {
                ForEach(BuiltInThemes.all) { candidate in
                    ThemeSwatchView(
                        theme: candidate,
                        isSelected: candidate.id == appModel.settings.selectedThemeID
                    ) {
                        withAnimation(AnimationTokens.standard) {
                            appModel.setTheme(id: candidate.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Zoom (scroll mode)

    private var zoomSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            sectionLabel("Zoom")
            HStack(spacing: SpacingTokens.sm) {
                Button {
                    session.setZoom(session.zoom - 0.25)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 44)
                }
                .accessibilityLabel(Text("Zoom out"))

                Text("\(Int(session.zoom * 100))%")
                    .font(TypographyTokens.callout)
                    .monospacedDigit()
                    .frame(width: 56)

                Button {
                    session.setZoom(session.zoom + 0.25)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44)
                }
                .accessibilityLabel(Text("Zoom in"))

                Spacer()

                Button("Reset") {
                    session.setZoom(1.0)
                }
                .disabled(session.zoom == 1.0)
            }
        }
    }

    // MARK: - Typography (reflow mode)

    private var typographySection: some View {
        @Bindable var settings = appModel.settings

        return VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            sectionLabel("Typography")
            Picker("Font", selection: $settings.reflowFontID) {
                Text("Serif").tag("serif")
                Text("Sans").tag("sans")
                Text("Rounded").tag("rounded")
                Text("Mono").tag("mono")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Slider(value: $settings.reflowTextSize, in: 14...30, step: 1) {
                Text("Text Size")
            } minimumValueLabel: {
                Text("A").font(.system(size: 11))
            } maximumValueLabel: {
                Text("A").font(.system(size: 20))
            }
        }
    }

    // MARK: - Focus

    private var focusRow: some View {
        Button(action: enterFocusMode) {
            HStack {
                Label("Focus Mode", systemImage: "rectangle.center.inset.filled")
                Spacer()
                Text("⇧⌘F")
                    .font(TypographyTokens.monospaceCaption)
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Hide everything but the page. Press Esc to exit.")
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(TypographyTokens.caption.weight(.medium))
            .foregroundStyle(ColorTokens.chromeSecondaryText)
            .textCase(.uppercase)
    }
}
