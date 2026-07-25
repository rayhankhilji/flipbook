import AppKit
import Observation
import SwiftUI

/// Grabs the hosting `NSWindow` once the SwiftUI view is actually attached to one (via
/// `viewDidMoveToWindow`, which fires at the right moment — unlike a bare async peek at
/// `.window`, which runs before the view has a window), and hands it back so the
/// `WindowManager` can drive full-screen transitions.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowResolvingView {
        let view = WindowResolvingView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: WindowResolvingView, context: Context) {
        nsView.onResolve = onResolve
    }
}

final class WindowResolvingView: NSView {
    var onResolve: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        onResolve?(window)
    }
}

/// Drives the reading window's full-screen transitions.
///
/// The window's *size* is owned by SwiftUI: the scene uses `.windowResizability(.contentSize)`
/// and `LibraryView` pins a fixed frame while browsing, which makes the library window compact
/// and non-resizable; opening a book relaxes the frame and this manager takes the window full
/// screen. `.fullScreenPrimary` lets the green traffic-light button work as a manual toggle,
/// and `isRestorable = false` stops a stale frame from a previous session overriding the pin.
@MainActor
@Observable
final class WindowManager {
    /// The fixed content size of the library / home window. Wide enough that the sidebar and
    /// content columns always stay side-by-side rather than collapsing into a flaky overlay.
    static let librarySize = CGSize(width: 1000, height: 680)

    private(set) weak var window: NSWindow?

    /// Invoked when the user leaves full screen (e.g. the green traffic-light button), so the
    /// library can drop the open book and return to its compact windowed state.
    var onExitFullScreen: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isRestorable = false
        registerObservers(for: window)
    }

    /// Takes the window to full screen for an immersive reading view.
    func enterReading() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }

    /// Leaves full screen; SwiftUI then re-pins the compact size via the library's fixed frame.
    func exitReading() {
        guard let window, window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }

    private func registerObservers(for window: NSWindow) {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
        observers.append(center.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onExitFullScreen?()
                self.window?.center()
            }
        })
    }
}
