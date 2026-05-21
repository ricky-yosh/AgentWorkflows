import AppKit
import SwiftTerm

/// A `LocalProcessTerminalView` that preserves the user's scroll position
/// while a CLI agent is producing output, and handles Shift+Enter for
/// inserting a newline without submitting.
///
/// Without this, every linefeed resets the viewport to the bottom, making it
/// impossible to scroll up and read earlier output while a process runs.
///
/// **Architecture**
///
/// SwiftTerm's ``Terminal`` has an internal `userScrolling` flag that is
/// **never set to true** by any production code.  As a result,
/// ``Terminal.scroll()`` always snaps `yDisp` to `yBase` (the bottom of the
/// buffer).  We work around this at two levels:
///
/// 1. ``scrolled(source:yDisp:)`` (``open`` on ``MacTerminalView``) is the
///    ``TerminalDelegate`` callback fired by ``Terminal.scroll()``.  By
///    overriding it we correct `yDisp` **before** the view updates, avoiding
///    any visible flicker.
///
/// 2. ``scrollWheel(with:)`` is replaced via ``class_addMethod`` (the method
///    is `public` not `open`, so a Swift `override` is not allowed across
///    modules).  The replacement tracks the user's scroll position so the
///    delegate override knows what row to pin the viewport to.
///
/// Tracking persists until the user scrolls all the way to the bottom,
/// matching the default behaviour of Terminal.app and iTerm2.
///
/// **Shift+Enter**
///
/// ``keyDown(with:)`` is similarly replaced.  When the user presses
/// Shift+Return, the running CLI receives a bare `\n` (line feed) and a
/// CR+LF is echoed locally so the newline is visible.
final class ScrollTrackingTerminalView: LocalProcessTerminalView {

    // ----------------------------------------------------------------
    // MARK: - Scroll-tracking state
    // ----------------------------------------------------------------

    private var isTrackingScroll = false
    private var userScrollTarget: Int?

    // ----------------------------------------------------------------
    // MARK: - Init / deinit
    // ----------------------------------------------------------------

    override init(frame: CGRect) {
        Self.installOverrides()
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        Self.installOverrides()
        super.init(coder: coder)
    }

    // ----------------------------------------------------------------
    // MARK: - TerminalDelegate (MacTerminalView) — process-driven scroll
    // ----------------------------------------------------------------

    /// Intercepts ``Terminal.scroll()`` before the viewport updates.
    /// When the user has manually scrolled up, this prevents every
    /// line of process output from snapping `yDisp` back to the bottom.
    override func scrolled(source terminal: Terminal, yDisp: Int) {
        if isTrackingScroll,
           let target = userScrollTarget,
           terminal.buffer.yDisp > target
        {
            // Terminal.scroll() just set yDisp = yBase (bottom).
            // Pin the viewport back to where the user was reading.
            terminal.buffer.yDisp = target
        }
        super.scrolled(source: terminal, yDisp: yDisp)
    }

    // ----------------------------------------------------------------
    // MARK: - ObjC-runtime overrides
    // ----------------------------------------------------------------

    private static let overridesInstalled: Void = {
        overrideScrollWheel()
        overrideKeyDown()
    }()

    private static func installOverrides() {
        _ = overridesInstalled
    }

    // ----------------------------------------------------------------
    // MARK: - scrollWheel override
    // ----------------------------------------------------------------

    private static func overrideScrollWheel() {
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

            self.isTrackingScroll = true

            original(self, selector, event)

            if self.scrollPosition >= 1.0 {
                // User scrolled to the bottom — resume normal auto-scroll.
                self.isTrackingScroll = false
                self.userScrollTarget = nil
                return
            }

            self.userScrollTarget = self.terminal.buffer.yDisp
        }

        let imp = imp_implementationWithBlock(block)
        class_addMethod(ScrollTrackingTerminalView.self, selector, imp, typeEncoding)
    }

    // ----------------------------------------------------------------
    // MARK: - keyDown override (Shift+Enter)
    // ----------------------------------------------------------------

    private static func overrideKeyDown() {
        let selector = #selector(NSResponder.keyDown(with:))
        guard let nsViewMethod = class_getInstanceMethod(NSView.self, selector) else { return }
        let typeEncoding = method_getTypeEncoding(nsViewMethod)

        let superImp = class_getMethodImplementation(LocalProcessTerminalView.self, selector)
        typealias KeyDownIMP = @convention(c) (AnyObject, Selector, NSEvent) -> Void
        let original = unsafeBitCast(superImp, to: KeyDownIMP.self)

        let block: @convention(block) (ScrollTrackingTerminalView, NSEvent) -> Void = { `self`, event in
            let significantModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
            let isShiftEnter = event.keyCode == 36
                && event.modifierFlags.intersection(significantModifiers) == .shift

            guard isShiftEnter else {
                original(self, selector, event)
                return
            }

            if let p = self.process {
                p.send(data: ArraySlice([0x0A]))
            }
            self.feed(byteArray: ArraySlice([0x0D, 0x0A]))
        }

        let imp = imp_implementationWithBlock(block)
        class_addMethod(ScrollTrackingTerminalView.self, selector, imp, typeEncoding)
    }
}
