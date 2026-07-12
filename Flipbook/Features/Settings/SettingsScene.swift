import FlipbookCore
import FlipbookDesignSystem
import SwiftData
import SwiftUI

/// Native macOS Settings window. Every control binds live to the `AppSettings`
/// singleton — changes apply immediately, no save button, per platform convention.
struct SettingsRootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        TabView {
            ReadingSettingsTab()
                .tabItem { Label("Reading", systemImage: "book") }
            DisplaySettingsTab()
                .tabItem { Label("Display", systemImage: "sparkles.tv") }
            NavigationSettingsTab()
                .tabItem { Label("Navigation", systemImage: "hand.draw") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 480)
    }
}

// MARK: - Reading

private struct ReadingSettingsTab: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var settings = appModel.settings

        Form {
            Section("Theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: SpacingTokens.md)], spacing: SpacingTokens.md) {
                    ForEach(BuiltInThemes.all) { theme in
                        ThemeSwatchView(
                            theme: theme,
                            isSelected: theme.id == settings.selectedThemeID
                        ) {
                            withAnimation(AnimationTokens.standard) {
                                appModel.setTheme(id: theme.id)
                            }
                        }
                    }
                }
                .padding(.vertical, SpacingTokens.xs)

                Text("Dark themes work best with text-based PDFs. Scanned or photo-based pages are dimmed rather than inverted.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
            }

            Section("Page") {
                LabeledContent("Warmth") {
                    Slider(value: $settings.warmthAdjustment, in: -0.4...0.4) {
                        Text("Warmth")
                    } minimumValueLabel: {
                        Image(systemName: "thermometer.snowflake").font(.caption)
                    } maximumValueLabel: {
                        Image(systemName: "thermometer.sun").font(.caption)
                    }
                    .frame(width: 220)
                }

                LabeledContent("Brightness") {
                    Slider(value: $settings.brightnessAdjustment, in: -0.25...0.25) {
                        Text("Brightness")
                    } minimumValueLabel: {
                        Image(systemName: "sun.min").font(.caption)
                    } maximumValueLabel: {
                        Image(systemName: "sun.max").font(.caption)
                    }
                    .frame(width: 220)
                }

                Button("Reset Adjustments") {
                    withAnimation(AnimationTokens.quick) {
                        settings.warmthAdjustment = 0
                        settings.brightnessAdjustment = 0
                    }
                }
                .disabled(settings.warmthAdjustment == 0 && settings.brightnessAdjustment == 0)
            }

            Section("Behavior") {
                Picker("New books open in", selection: $settings.defaultNavigationMode) {
                    Text("Page Turning").tag(NavigationMode.pageTurn)
                    Text("Continuous Scrolling").tag(NavigationMode.scroll)
                }

                Toggle("Auto-hide toolbar in full screen", isOn: $settings.fullscreenAutoHideToolbar)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Display

private struct DisplaySettingsTab: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var settings = appModel.settings

        Form {
            Section("Animation") {
                LabeledContent("Speed") {
                    Slider(value: $settings.animationSpeed, in: 0.5...2.0, step: 0.25) {
                        Text("Animation Speed")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise").font(.caption)
                    } maximumValueLabel: {
                        Image(systemName: "hare").font(.caption)
                    }
                    .frame(width: 220)
                }
                Text("System Reduce Motion always takes precedence.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
            }

            Section("Layout") {
                Picker("Interface density", selection: $settings.interfaceDensity) {
                    Text("Comfortable").tag(InterfaceDensity.comfortable)
                    Text("Compact").tag(InterfaceDensity.compact)
                }

                LabeledContent("Default zoom") {
                    Slider(value: $settings.defaultZoom, in: 0.5...2.0, step: 0.25) {
                        Text("Default Zoom")
                    }
                    .frame(width: 220)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Navigation

private struct NavigationSettingsTab: View {
    @Environment(AppModel.self) private var appModel

    private let shortcuts: [(String, String)] = [
        ("Next page", "→ or Space"),
        ("Previous page", "←"),
        ("Go to page…", "Click the page indicator"),
        ("Bookmark page", "⌘D"),
        ("Toggle sidebar", "⌥⌘S"),
        ("Zoom in / out", "⌘+ / ⌘−"),
        ("Actual size", "⌘0"),
        ("Import PDF", "⌘O"),
        ("Full screen", "⌃⌘F"),
    ]

    var body: some View {
        @Bindable var settings = appModel.settings

        Form {
            Section("Trackpad") {
                Toggle("Swipe to turn pages", isOn: $settings.gestureSwipeToTurnPage)
                Toggle("Pinch to zoom", isOn: $settings.gesturePinchToZoom)
            }

            Section("Keyboard Shortcuts") {
                ForEach(shortcuts, id: \.0) { name, keys in
                    LabeledContent(name) {
                        Text(keys)
                            .font(TypographyTokens.monospaceCaption)
                            .foregroundStyle(ColorTokens.chromeSecondaryText)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var settings = appModel.settings

        Form {
            Section("Accent") {
                HStack(spacing: SpacingTokens.md) {
                    ForEach(ColorTokens.accentOptions) { option in
                        Button {
                            settings.accentColorID = option.id
                        } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.primary.opacity(settings.accentColorID == option.id ? 0.8 : 0), lineWidth: 2)
                                        .padding(-3)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(option.name))
                        .accessibilityAddTraits(
                            settings.accentColorID == option.id ? [.isButton, .isSelected] : .isButton
                        )
                        .help(option.name)
                    }
                }
                .padding(.vertical, SpacingTokens.xs)
            }

            Section("Chrome") {
                Toggle("Translucent sidebar and toolbar", isOn: $settings.uiTransparencyEnabled)
                Toggle("Show sidebar when opening a book", isOn: $settings.sidebarVisibleByDefault)
            }
        }
        .formStyle(.grouped)
    }
}
