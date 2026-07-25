import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static var schema: Schema {
        Schema([
            Book.self,
            ReadingProgress.self,
            Bookmark.self,
            Highlight.self,
            ThemeOverride.self,
            AppSettings.self,
            Folder.self,
            StickyNote.self,
            ReadingDay.self,
        ])
    }

    /// Creates the app's single shared `ModelContainer`. Pass `inMemory: true` for tests
    /// and previews so nothing touches the user's real library.
    @MainActor
    public static func make(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        ensureSettingsSingleton(in: container)
        return container
    }

    /// Guarantees exactly one `AppSettings` row exists, creating it on first launch.
    @MainActor
    private static func ensureSettingsSingleton(in container: ModelContainer) {
        let context = container.mainContext
        let descriptor = FetchDescriptor<AppSettings>()
        let existing = (try? context.fetch(descriptor)) ?? []
        if existing.isEmpty {
            context.insert(AppSettings())
            try? context.save()
        }
    }
}
