import AppKit
import SwiftUI

/// Placed in the `.background()` of the terminal pane inside `HSplitView`.
/// Walks up to the ancestor NSSplitView to:
///   - restore the saved divider position before the first render (same pattern as InspectorLayoutFixer)
///   - write position back to TerminalDividerState only on drag-end (debounced) to avoid per-frame re-renders
struct SplitViewBridge: NSViewRepresentable {
    let state: TerminalDividerState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> BridgeView {
        BridgeView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {}

    // MARK: - BridgeView

    final class BridgeView: NSView {
        unowned let coordinator: Coordinator
        private var initialPositionSet = false

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                coordinator.attach(to: ancestorSplitView())
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                coordinator.detach()
            }
        }

        override func layout() {
            super.layout()
            guard !initialPositionSet,
                  let splitView = ancestorSplitView(),
                  splitView.bounds.width > 0 else { return }
            initialPositionSet = true
            splitView.setPosition(coordinator.state.width, ofDividerAt: 0)
        }

        private func ancestorSplitView() -> NSSplitView? {
            var v: NSView? = superview
            while let view = v {
                if let split = view as? NSSplitView { return split }
                v = view.superview
            }
            return nil
        }
    }

    // MARK: - Coordinator

    @MainActor final class Coordinator {
        let state: TerminalDividerState
        private var observerToken: NSObjectProtocol?
        private var persistTimer: Timer?
        private var lastSeenWidth: CGFloat = 0

        init(state: TerminalDividerState) { self.state = state }

        func attach(to splitView: NSSplitView?) {
            guard let splitView, observerToken == nil else { return }
            observerToken = NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: splitView,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated { self?.handleResize(notification) }
            }
        }

        func detach() {
            if let token = observerToken {
                NotificationCenter.default.removeObserver(token)
                observerToken = nil
            }
            persistTimer?.invalidate()
            persistTimer = nil
        }

        private func handleResize(_ notification: Notification) {
            guard let splitView = notification.object as? NSSplitView,
                  let leftPane = splitView.subviews.first,
                  !splitView.isSubviewCollapsed(leftPane) else { return }

            lastSeenWidth = leftPane.frame.width

            // Debounce: only update state and persist after drag settles.
            // No per-frame state mutations → no per-frame SessionDetailView re-renders.
            persistTimer?.invalidate()
            persistTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.state.updateFromAppKit(width: self.lastSeenWidth)
                    self.state.persist()
                }
            }
        }
    }
}
