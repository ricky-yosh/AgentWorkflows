import AppKit
import SwiftUI

/// Injected into the inspector panel's background to force the NSSplitView divider
/// to the correct position before AppKit's first layout pass commits the wrong value.
struct InspectorLayoutFixer: NSViewRepresentable {
    let targetWidth: CGFloat

    func makeNSView(context: Context) -> InspectorLayoutFixerView {
        InspectorLayoutFixerView(targetWidth: targetWidth)
    }

    func updateNSView(_ nsView: InspectorLayoutFixerView, context: Context) {}
}

final class InspectorLayoutFixerView: NSView {
    let targetWidth: CGFloat
    private var hasAttemptedFix = false

    init(targetWidth: CGFloat) {
        self.targetWidth = targetWidth
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            fixDivider()
        }
    }

    override func layout() {
        super.layout()
        if !hasAttemptedFix {
            fixDivider()
        }
    }

    private func fixDivider() {
        hasAttemptedFix = true
        guard let splitView = ancestorInspectorSplitView() else { return }
        let position = splitView.bounds.width - targetWidth
        guard position > 0 else { return }
        splitView.setPosition(position, ofDividerAt: 0)
    }

    /// Walks up the view hierarchy to find the NSSplitView created by SwiftUI's
    /// .inspector() modifier. We stop at the first NSSplitView we encounter,
    /// which is the inspector split (not the outer NavigationSplitView).
    private func ancestorInspectorSplitView() -> NSSplitView? {
        var v: NSView? = superview
        while let view = v {
            if let split = view as? NSSplitView { return split }
            v = view.superview
        }
        return nil
    }
}
