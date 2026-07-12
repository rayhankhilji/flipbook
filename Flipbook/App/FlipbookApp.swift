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
                .frame(minWidth: 720, minHeight: 480)
        }
        .modelContainer(modelContainer)
        .windowStyle(.automatic)
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
