import SwiftUI
import SwiftTerm

/// Wraps a persistent `NSView` container that accumulates all terminal views
/// as subviews and shows/hides them as sessions change.
///
/// **Why a container instead of direct wrapping:**
/// SwiftUI destroys and recreates `NSViewRepresentable` on every session swap
/// because `ContentView` switches between `SessionDetailView` instances.
/// If the `LocalProcessTerminalView` is returned directly from `makeNSView`,
/// it loses its window on each swap — invalidating the Metal `CAMetalLayer`
/// drawable and blanking the TUI framebuffer.
///
/// By returning a stable container `NSView` from `makeNSView` and swapping
/// which terminal view is visible via `isHidden` in `updateNSView`, terminal
/// views are never removed from the window hierarchy. Their Metal drawables
/// are preserved, so TUI apps (e.g. OpenCode) restore correctly without
/// needing SIGWINCH or any PTY-level hacks.
struct TerminalViewWrapper: NSViewRepresentable {
    let terminalView: LocalProcessTerminalView

    final class Coordinator {
        var visibleView: LocalProcessTerminalView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        pin(terminalView, to: container)
        context.coordinator.visibleView = terminalView
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard context.coordinator.visibleView !== terminalView else { return }
        context.coordinator.visibleView?.isHidden = true
        if terminalView.superview !== container {
            pin(terminalView, to: container)
        }
        terminalView.isHidden = false
        context.coordinator.visibleView = terminalView
    }

    private func pin(_ view: LocalProcessTerminalView, to container: NSView) {
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }
}
