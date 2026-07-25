import FlipbookCore
import SwiftData
import SwiftUI

@main
struct FlipbookApp: App {
    let modelContainer = ModelContainerFactory.make()
    @State private var appModel: AppModel

    init() {
        let container = modelContainer
        _appModel = State(initialValue: AppModel(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(appModel)
                .tint(appModel.accentColor)
                .preferredColorScheme(appModel.preferredColorScheme)
        }
        .modelContainer(modelContainer)
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 680)
        // The library pins a fixed frame (see LibraryView), which under .contentSize
        // resizability makes the compact window non-user-resizable; while reading the frame
        // relaxes and the window runs full screen.
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import PDF…") {
                    NotificationCenter.default.post(name: .flipbookImportRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            ReaderMenuCommands()
        }

        Settings {
            SettingsRootView()
                .environment(appModel)
                .tint(appModel.accentColor)
        }
        .modelContainer(modelContainer)
    }
}

extension Notification.Name {
    static let flipbookImportRequested = Notification.Name("flipbookImportRequested")
}
