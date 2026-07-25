import FlipbookCore
import FlipbookDesignSystem
import IOKit.pwr_mgt
import Observation
import SwiftData
import SwiftUI

/// Root app-wide state — created once in `FlipbookApp`, injected via `.environment`.
/// Per-window reading state lives in `ReadingSession` instead (see Features/Reader),
/// not here, since each window can have a different book open.
@Observable
@MainActor
final class AppModel {
    let modelContext: ModelContext

    private(set) var settings: AppSettings

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.settings = AppModel.fetchSettings(in: modelContext)
        startNightClock()
    }

    // MARK: - Night mode

    /// Whether the clock is currently in night hours (20:00–07:00). Tracked so views using
    /// `currentTheme` refresh when the boundary passes.
    private(set) var isNightNow = AppModel.isNight(Date())
    private var nightTimer: Timer?

    static func isNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 20 || hour < 7
    }

    private func startNightClock() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let night = AppModel.isNight(Date())
                if night != self.isNightNow { self.isNightNow = night }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        nightTimer = timer
    }

    // MARK: - Reading time tracker
    //
    // A single app-wide clock that only advances while a book is actually open. Each open
    // reader calls `beginReading()`/`endReading()`; the elapsed time is flushed into today's
    // `ReadingDay` row on a periodic tick and whenever the last reader closes, so it survives
    // crashes and day rollovers without a heavy per-tick save.

    private var activeReaders = 0
    private var readingClock: Date?
    private var tickTimer: Timer?

    /// Whether any reader is currently open (drives the dashboard's live indicator).
    private(set) var isReading = false
    /// Seconds read in the current continuous reading session, for a live on-screen timer.
    private(set) var liveSessionSeconds: TimeInterval = 0

    func beginReading() {
        activeReaders += 1
        guard activeReaders == 1 else { return }
        isReading = true
        liveSessionSeconds = 0
        readingClock = Date()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushReading() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        updateKeepAwake()
    }

    func endReading() {
        activeReaders = max(0, activeReaders - 1)
        guard activeReaders == 0 else { return }
        flushReading()
        tickTimer?.invalidate()
        tickTimer = nil
        readingClock = nil
        isReading = false
        updateKeepAwake()
    }

    // MARK: - Keep awake

    private var sleepAssertionID = IOPMAssertionID(0)
    private var sleepAssertionActive = false

    /// Holds a display-sleep assertion while a book is open (if the setting is on), so the
    /// screen doesn't dim mid-chapter. Released the moment the last reader closes.
    private func updateKeepAwake() {
        let wanted = isReading && settings.keepAwakeWhileReading
        if wanted && !sleepAssertionActive {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Flipbook reading session" as CFString,
                &id
            )
            if result == kIOReturnSuccess {
                sleepAssertionID = id
                sleepAssertionActive = true
            }
        } else if !wanted && sleepAssertionActive {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionActive = false
        }
    }

    /// Adds the time elapsed since the last flush into today's `ReadingDay`.
    private func flushReading() {
        guard let start = readingClock else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(start)
        guard elapsed > 0 else { return }
        readingClock = now
        liveSessionSeconds += elapsed
        addSecondsToToday(elapsed)
    }

    private func addSecondsToToday(_ seconds: Double) {
        let key = ReadingDay.key(for: Date())
        let descriptor = FetchDescriptor<ReadingDay>(predicate: #Predicate { $0.dayKey == key })
        if let day = (try? modelContext.fetch(descriptor))?.first {
            day.seconds += seconds
        } else {
            modelContext.insert(ReadingDay(dayKey: key, date: Date(), seconds: seconds))
        }
        try? modelContext.save()
    }

    /// The active theme with the user's warmth/brightness adjustments merged in.
    /// Its `id` is a full render key, so passing it to the renderer automatically
    /// caches adjusted pages separately from unadjusted ones. During night hours (when
    /// night mode is on) the user's chosen night theme takes over automatically.
    var currentTheme: ThemeDefinition {
        let baseID = settings.nightModeEnabled && isNightNow
            ? settings.nightThemeID
            : settings.selectedThemeID
        return ThemeRenderKey.resolve(ThemeRenderKey.encode(
            baseID: baseID,
            warmth: settings.warmthAdjustment,
            brightness: settings.brightnessAdjustment
        ))
    }

    var accentColor: Color {
        ColorTokens.accent(for: settings.accentColorID)
    }

    /// Every palette token is dynamic (cream in light, chocolate-mocha in dark), so "System"
    /// genuinely follows macOS; Light/Dark pin the corresponding skin.
    var preferredColorScheme: ColorScheme? {
        switch settings.appAppearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func setAppearance(_ appearance: AppAppearance) {
        settings.appAppearance = appearance
        save()
    }

    /// Animation tokens scaled by the user's Settings > Display speed preference.
    func animation(_ base: AnimationKind) -> Animation {
        switch base {
        case .standard: AnimationTokens.standard(speedMultiplier: settings.animationSpeed)
        case .quick: AnimationTokens.quick(speedMultiplier: settings.animationSpeed)
        case .pageTurn: AnimationTokens.pageTurn(speedMultiplier: settings.animationSpeed)
        }
    }

    enum AnimationKind {
        case standard, quick, pageTurn
    }

    func setTheme(id: String) {
        settings.selectedThemeID = id
        save()
    }

    func save() {
        try? modelContext.save()
    }

    private static func fetchSettings(in context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let created = AppSettings()
        context.insert(created)
        try? context.save()
        return created
    }
}
