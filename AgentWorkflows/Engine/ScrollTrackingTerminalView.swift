import AppKit
import SwiftTerm

/// A `LocalProcessTerminalView` that preserves the user's scroll position
/// while a CLI agent is producing output.
///
/// Without this, every linefeed resets the viewport to the bottom, making it
/// impossible to scroll up and read earlier output while a process is running.
///
/// **How it works**
///
/// 1. ``scrollWheel(with:)`` is replaced via ``class_addMethod`` (the method
///    is `public` not `open` on ``TerminalView``, so a Swift `override` is
///    not allowed across modules).  The replacement saves the user's viewport
///    position and sets ``isTrackingScroll``.
///
/// 2. ``scrolled(source:position:)`` (``open`` on
///    ``LocalProcessTerminalView``) is overridden.  When the terminal engine
///    auto-scrolls after new output, we detect the unwanted viewport move and
///    restore the user's position via ``scrollTo(row:)``.
///
/// 3. A cooldown timer clears ``isTrackingScroll`` after the scroll gesture
///    (finger lift + momentum) ends, so auto-scroll resumes naturally.
final class ScrollTrackingTerminalView: LocalProcessTerminalView {

    // ----------------------------------------------------------------
    // MARK: - Scroll-tracking state
    // ----------------------------------------------------------------

    /// True while the user is actively scrolling or momentum is still
    /// running.  While set we will fight auto-scroll resets.
    private var isTrackingScroll = false

    /// The `yDisp` the user last scrolled to.  Restored when the terminal
    /// engine snaps the viewport back to the bottom.
    private var userScrollTarget: Int?

    /// Guard against re-entry when our ``scrolled`` handler calls
    /// ``scrollTo(row:)``, which itself triggers another ``scrolled`` call.
    private var isRestoringScroll = false

    /// Clears tracking after the gesture fully ends.
    private var scrollEndWorkItem: DispatchWorkItem?

    // ----------------------------------------------------------------
    // MARK: - Init / deinit
    // ----------------------------------------------------------------

    override init(frame: CGRect) {
        Self.installScrollWheelOverride()
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        Self.installScrollWheelOverride()
        super.init(coder: coder)
    }

    deinit {
        scrollEndWorkItem?.cancel()
    }

    // ----------------------------------------------------------------
    // MARK: - scrolled delegate (open on LocalProcessTerminalView)
    // ----------------------------------------------------------------

    override func scrolled(source: TerminalView, position: Double) {
        guard !isRestoringScroll else {
            isRestoringScroll = false
            super.scrolled(source: source, position: position)
            return
        }

        // If the terminal just auto-scrolled to the bottom but the user
        // had scrolled up, restore the user's viewport.
        if isTrackingScroll,
           let target = userScrollTarget,
           scrollPosition >= 1.0,
           terminal.buffer.yDisp < target
        {
            isRestoringScroll = true
            scrollTo(row: target)
            return
        }

        super.scrolled(source: source, position: position)
    }

    // ----------------------------------------------------------------
    // MARK: - scrollWheel override (via ObjC runtime)
    // ----------------------------------------------------------------

    /// Replaces the inherited `scrollWheel(with:)` at the ObjC level
    /// so we can track scroll position and toggle ``isTrackingScroll``.
    private static let swizzled: Void = {
        let selector = #selector(NSResponder.scrollWheel(with:))
        guard let nsViewMethod = class_getInstanceMethod(NSView.self, selector) else { return }
        let typeEncoding = method_getTypeEncoding(nsViewMethod)

        let superImp = class_getMethodImplementation(LocalProcessTerminalView.self, selector)
        typealias ScrollWheelIMP = @convention(c) (AnyObject, Selector, NSEvent) -> Void
        let original = unsafeBitCast(superImp, to: ScrollWheelIMP.self)

        let block: @convention(block) (ScrollTrackingTerminalView, NSEvent) -> Void = { `self`, event in
            guard event.deltaY != 0 else {
                original(self, selector, event)
                return
            }

            self.scrollEndWorkItem?.cancel()
            self.scrollEndWorkItem = nil

            self.isTrackingScroll = true

            original(self, selector, event)

            let currentYDisp = self.terminal.buffer.yDisp

            // If the viewport reached the bottom, re-enable auto-scroll
            // so new output scrolls naturally from this point.
            if self.scrollPosition >= 1.0 {
                self.isTrackingScroll = false
                self.userScrollTarget = nil
                return
            }

            // Save the viewport position the user scrolled to.
            self.userScrollTarget = currentYDisp

            // Schedule a clear once the full gesture ends.
            // Trackpad: phase .began→.changed→.ended →
            //   momentumPhase .began→.changed→.ended
            // Mouse wheel: phase & momentumPhase are .none per tick.
            let gestureEnded = event.phase == .ended || event.phase == .cancelled
            let momentumEnded = event.momentumPhase == .ended || event.momentumPhase == .cancelled
            let noMomentum = event.momentumPhase == .none
            let isMouseWheel = event.phase == .none && event.momentumPhase == .none

            if (gestureEnded && (momentumEnded || noMomentum)) || momentumEnded || isMouseWheel {
                scheduleClear(self)
            }
        }

        let imp = imp_implementationWithBlock(block)
        class_addMethod(ScrollTrackingTerminalView.self, selector, imp, typeEncoding)
    }()

    private static func installScrollWheelOverride() {
        _ = swizzled
    }

    // ----------------------------------------------------------------
    // MARK: - Cooldown
    // ----------------------------------------------------------------

    private static func scheduleClear(_ view: ScrollTrackingTerminalView) {
        let work = DispatchWorkItem { [weak view] in
            view?.isTrackingScroll = false
            view?.userScrollTarget = nil
        }
        view.scrollEndWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
