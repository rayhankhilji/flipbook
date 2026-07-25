import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// Continuous-scroll navigation mode, backed by the native `PageScrollNSView` engine —
/// AppKit owns scrolling and trackpad magnification (smooth, cursor-anchored, no SwiftUI
/// scroll-position tug-of-war); SwiftUI rides on top per page for annotations and notes.
struct ContinuousScrollView: NSViewRepresentable {
    let session: ReadingSession
    let theme: ThemeDefinition
    var magnifyEnabled = true

    func makeNSView(context: Context) -> PageScrollNSView {
        let view = PageScrollNSView()
        view.configure(session: session)
        view.apply(theme: theme, zoom: session.zoom, magnifyEnabled: magnifyEnabled)
        DispatchQueue.main.async {
            view.scrollToPage(session.currentPageIndex, animated: false)
        }
        return view
    }

    func updateNSView(_ view: PageScrollNSView, context: Context) {
        view.apply(theme: theme, zoom: session.zoom, magnifyEnabled: magnifyEnabled)
        if let request = session.scrollToRequest {
            view.scrollToPage(request.pageIndex)
            DispatchQueue.main.async {
                session.scrollToRequest = nil
            }
        }
    }
}
