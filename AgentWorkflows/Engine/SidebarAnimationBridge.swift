import AppKit
import SwiftUI

/// Placed in the detail column's background to detect when NavigationSplitView
/// commits a sidebar-open snap (no intermediate frames) and smooth it using
/// AppKit's NSAnimationContext + animator(), so the detail column transitions
/// smoothly instead of jumping.
struct SidebarAnimationBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        private var observation: NSKeyValueObservation?
        private weak var observedView: NSView?
        private var lastWidth: CGFloat = 0
        private var isAnimating = false

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let parent = view?.superview else { return }
                self.lastWidth = parent.frame.width
                self.observedView = parent
                self.observation = parent.observe(\.frame, options: [.new, .old]) { [weak self] _, change in
                    self?.handleFrameChange(change: change)
                }
            }
        }

        private func handleFrameChange(change: NSKeyValueObservedChange<CGRect>) {
            guard !isAnimating,
                  let oldW = change.oldValue?.width,
                  let newW = change.newValue?.width,
                  oldW != newW else { return }
            let delta = abs(newW - oldW)
            guard delta > 100 else { return }

            isAnimating = true

            DispatchQueue.main.async { [weak self] in
                guard let self, let view = self.observedView else {
                    self?.isAnimating = false
                    return
                }

                var startFrame = view.frame
                startFrame.size.width = oldW
                view.frame = startFrame

                var endFrame = view.frame
                endFrame.size.width = newW

                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    view.animator().frame = endFrame
                }, completionHandler: { [weak self] in
                    self?.isAnimating = false
                })
            }
        }
    }
}
