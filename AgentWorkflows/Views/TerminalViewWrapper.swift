import SwiftUI
import SwiftTerm

/// Wraps a persistent `NSView` container that accumulates all terminal views
/// as subviews and shows/hides them as sessions change.
///
/// **Why always-present, with optional terminalView:**
/// When a session has no active engine the caller passes `nil`.  The container
/// stays in the SwiftUI view tree so the previously-visible terminal view is
/// never removed from the window hierarchy.  Removing a view from a window
/// invalidates its `CAMetalLayer` drawable, blanking full-screen TUI apps
/// (e.g. OpenCode / Bubble Tea) — even if the view is re-inserted later.
///
/// Passing a non-nil `terminalView` shows that view and hides the previous
/// one; both remain as subviews of the container.
struct TerminalViewWrapper: NSViewRepresentable {
    /// The terminal view to show, or `nil` to hide the current view while
    /// keeping it (and the container) alive in the window hierarchy.
    let terminalView: LocalProcessTerminalView?

    final class Coordinator {
        var visibleView: LocalProcessTerminalView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        if let tv = terminalView {
            pin(tv, to: container)
            context.coordinator.visibleView = tv
        }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard context.coordinator.visibleView !== terminalView else {
            return
        }

        if let tv = terminalView {
            // Switch to a new terminal view — keep all previous views as hidden subviews.
            context.coordinator.visibleView?.isHidden = true
            if tv.superview !== container {
                pin(tv, to: container)
            }
            tv.isHidden = false
            context.coordinator.visibleView = tv
        } else {
            // nil: hide the current view but leave it (and the container) in the hierarchy.
            context.coordinator.visibleView?.isHidden = true
            context.coordinator.visibleView = nil
        }
    }

    private func pin(_ view: LocalProcessTerminalView, to container: NSView) {
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }
}
