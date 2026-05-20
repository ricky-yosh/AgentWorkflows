import AppKit
import SwiftTerm

/// A `LocalProcessTerminalView` that preserves the user's scroll position
/// while a CLI agent is producing output, and handles Shift+Enter for
/// inserting a newline without submitting.
///
/// **Scroll persistence**
///
/// Without this, every linefeed resets the viewport to the bottom, making it
/// impossible to scroll up and read earlier output while a process runs.
///
/// ``scrollWheel(with:)`` is replaced via ``class_addMethod`` (the method is
/// `public` not `open` on ``TerminalView``, so a Swift `override` is not
/// allowed across modules).  The replacement saves the user's viewport
/// position.  ``scrolled(source:position:)`` (``open`` on
/// ``LocalProcessTerminalView``) detects when the engine snaps `yDisp` to the
/// bottom and restores the user's scroll position.
///
/// **Shift+Enter**
///
/// ``keyDown(with:)`` is similarly replaced.  When the user presses
/// Shift+Return, the running CLI receives a bare `\n` (line feed) so it
/// inserts a line break instead of submitting the prompt.  Since the running
/// CLI may have `ECHO` off, the newline is also echoed locally to the
/// terminal display via ``feed(byteArray:)``.
final class ScrollTrackingTerminalView: LocalProcessTerminalView {

    // ----------------------------------------------------------------
    // MARK: - Scroll-tracking state
    // ----------------------------------------------------------------

    private var isTrackingScroll = false
    private var userScrollTarget: Int?
    private var isRestoringScroll = false
    private var scrollEndWorkItem: DispatchWorkItem?

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

            self.scrollEndWorkItem?.cancel()
            self.scrollEndWorkItem = nil

            self.isTrackingScroll = true

            original(self, selector, event)

            if self.scrollPosition >= 1.0 {
                self.isTrackingScroll = false
                self.userScrollTarget = nil
                return
            }

            self.userScrollTarget = self.terminal.buffer.yDisp

            let gestureEnded = event.phase.contains(.ended) || event.phase.contains(.cancelled)
            let momentumEnded = event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
            let noMomentum = event.momentumPhase.isEmpty
            let isMouseWheel = event.phase.isEmpty && event.momentumPhase.isEmpty

            if (gestureEnded && (momentumEnded || noMomentum)) || momentumEnded || isMouseWheel {
                scheduleClear(self)
            }
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

            // Send a bare newline to the process for a line break, and echo
            // a CR+LF locally so it shows on screen even when ECHO is off.
            if let p = self.process {
                p.send(data: ArraySlice([0x0A]))
            }
            self.feed(byteArray: ArraySlice([0x0D, 0x0A]))
        }

        let imp = imp_implementationWithBlock(block)
        class_addMethod(ScrollTrackingTerminalView.self, selector, imp, typeEncoding)
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
