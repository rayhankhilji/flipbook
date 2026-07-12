import SwiftUI

/// Reader actions reachable from the menu bar. Routed by notification because menu
/// commands live outside the reader's view hierarchy while the active `ReadingSession`
/// is per-window state.
enum ReaderCommand {
    case nextPage
    case previousPage
    case toggleSidebar
    case toggleFocusMode
    case toggleBookmark
    case toggleNavigationMode
    case zoomIn
    case zoomOut
    case zoomReset
    case toggleReflow
}

extension Notification.Name {
    static let flipbookReaderCommand = Notification.Name("flipbookReaderCommand")
}

struct ReaderMenuCommands: Commands {
    private func post(_ command: ReaderCommand) {
        NotificationCenter.default.post(name: .flipbookReaderCommand, object: command)
    }

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Next Page") { post(.nextPage) }
                .keyboardShortcut("]", modifiers: .command)

            Button("Previous Page") { post(.previousPage) }
                .keyboardShortcut("[", modifiers: .command)

            Divider()

            Button("Toggle Reading Sidebar") { post(.toggleSidebar) }
                .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Focus Mode") { post(.toggleFocusMode) }
                .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Switch Reading Mode") { post(.toggleNavigationMode) }

            Button("Reflow Text") { post(.toggleReflow) }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Zoom In") { post(.zoomIn) }
                .keyboardShortcut("=", modifiers: .command)

            Button("Zoom Out") { post(.zoomOut) }
                .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") { post(.zoomReset) }
                .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button("Bookmark This Page") { post(.toggleBookmark) }
                .keyboardShortcut("d", modifiers: .command)
        }
    }
}
