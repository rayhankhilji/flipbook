import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// SwiftUI host for the Core Animation page-turn surface. This is the one place the
/// reader drops to AppKit: an interactive, interruptible, gesture-tracked page turn
/// isn't expressible with SwiftUI's fire-and-forget transitions.
struct PageTurnContainerView: NSViewRepresentable {
    let session: ReadingSession
    let theme: ThemeDefinition
    let swipeEnabled: Bool

    func makeNSView(context: Context) -> PageTurnNSView {
        let view = PageTurnNSView()
        view.configure(session: session)
        view.onPageCommitted = { index in
            session.setCurrentPage(index)
        }
        applyProperties(to: view)
        return view
    }

    func updateNSView(_ view: PageTurnNSView, context: Context) {
        applyProperties(to: view)
        // External navigation (page-jump popover, keyboard while a jump request is
        // pending) — the view animates and commits back via onPageCommitted.
        if let request = session.scrollToRequest {
            view.navigate(to: request.pageIndex)
            DispatchQueue.main.async {
                session.scrollToRequest = nil
            }
        } else if view.displayedIndex != session.currentPageIndex {
            view.navigate(to: session.currentPageIndex)
        }
    }

    private func applyProperties(to view: PageTurnNSView) {
        view.swipeGestureEnabled = swipeEnabled
        view.update(
            themeID: theme.id,
            pageBackground: theme.pageBackground.cgColor,
            canvas: canvasCGColor,
            isDark: theme.isDark
        )
    }

    private var canvasCGColor: CGColor {
        let bg = theme.pageBackground
        if theme.isDark {
            return CGColor(
                red: min(bg.red + 0.045, 1),
                green: min(bg.green + 0.045, 1),
                blue: min(bg.blue + 0.045, 1),
                alpha: 1
            )
        }
        return CGColor(red: bg.red * 0.93, green: bg.green * 0.93, blue: bg.blue * 0.93, alpha: 1)
    }
}
