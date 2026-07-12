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
            AISettingsTab()
                .tabItem { Label("AI", systemImage: "sparkles") }
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
            Section("Theme") {
                Picker("Appearance", selection: Binding(
                    get: { settings.appAppearance },
                    set: { appModel.setAppearance($0) }
                )) {
                    ForEach(AppAppearance.allCases, id: \.self) { option in
                        Label(option.label, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text("Controls the app's window, sidebar, and menus. Page content is styled by the per-book reading theme instead.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
            }

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

// MARK: - AI (bring-your-own-key)

private struct AISettingsTab: View {
    @Environment(AppModel.self) private var appModel

    @State private var apiKeyField = ""
    @State private var hasStoredKey = false
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }

    private var provider: AIProvider { appModel.settings.aiProvider }

    var body: some View {
        @Bindable var settings = appModel.settings

        Form {
            Section("Provider") {
                Picker("Provider", selection: Binding(
                    get: { settings.aiProvider },
                    set: { switchProvider(to: $0) }
                )) {
                    ForEach(AIProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                Text(provider.note)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
            }

            Section("\(provider.displayName) API Key") {
                Text("Flipbook uses your own key. It's stored only in your Mac's Keychain and sent directly to \(provider.displayName) over a secure connection — never to us. Each provider has its own key.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.chromeSecondaryText)

                SecureField(hasStoredKey ? "•••• stored in Keychain" : provider.keyPlaceholder, text: $apiKeyField)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Key") {
                        AIKeychain.save(apiKeyField, for: provider)
                        apiKeyField = ""
                        refreshKeyState()
                        testState = .idle
                    }
                    .buttonStyle(.flipbook(prominent: true))
                    .disabled(apiKeyField.trimmingCharacters(in: .whitespaces).isEmpty)

                    if hasStoredKey {
                        Button("Remove", role: .destructive) {
                            AIKeychain.delete(for: provider)
                            refreshKeyState()
                            testState = .idle
                        }
                    }
                    Spacer()
                    testStatusView
                }

                Button {
                    runTest()
                } label: {
                    Label("Test Connection", systemImage: "checkmark.seal")
                }
                .disabled(!hasStoredKey || testState == .testing)

                Link("Get a \(provider.displayName) key", destination: provider.consoleURL)
                    .font(TypographyTokens.caption)
            }

            Section("Model") {
                // A text field (so YUNWU's arbitrary model IDs work) with a preset menu
                // scoped to the current provider.
                HStack {
                    TextField("Model ID", text: Binding(
                        get: { settings.aiModelID },
                        set: { settings.aiModelID = $0; appModel.save() }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Menu("Presets") {
                        ForEach(provider.models) { option in
                            Button(option.name) {
                                settings.aiModelID = option.id
                                appModel.save()
                            }
                        }
                    }
                    .fixedSize()
                }
                if let blurb = provider.models.first(where: { $0.id == settings.aiModelID })?.blurb {
                    Text(blurb)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.chromeSecondaryText)
                } else if provider.allowsCustomModel {
                    Text("Enter any model ID this relay supports.")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.chromeSecondaryText)
                }
            }

            Section("Features") {
                Toggle("Enable AI features", isOn: $settings.aiEnabled)
                    .disabled(!hasStoredKey)
                    .onChange(of: settings.aiEnabled) { _, _ in appModel.save() }

                Toggle("Allow web search in conversations", isOn: $settings.aiWebSearchEnabled)
                    .disabled(!hasStoredKey)
                    .onChange(of: settings.aiWebSearchEnabled) { _, _ in appModel.save() }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshKeyState)
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(TypographyTokens.caption)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(TypographyTokens.caption)
                .lineLimit(2)
        }
    }

    private func switchProvider(to newProvider: AIProvider) {
        appModel.settings.aiProvider = newProvider
        // Default to the new provider's flagship model unless the user already typed one
        // that belongs to it.
        if !newProvider.models.contains(where: { $0.id == appModel.settings.aiModelID }) {
            appModel.settings.aiModelID = newProvider.defaultModelID
        }
        appModel.save()
        apiKeyField = ""
        testState = .idle
        refreshKeyState()
    }

    private func refreshKeyState() {
        hasStoredKey = AIKeychain.hasKey(for: provider)
    }

    private func runTest() {
        testState = .testing
        let p = provider
        let modelID = appModel.settings.aiModelID
        Task {
            do {
                try await AIService.shared.validateKey(provider: p, modelID: modelID)
                testState = .success
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }
}
