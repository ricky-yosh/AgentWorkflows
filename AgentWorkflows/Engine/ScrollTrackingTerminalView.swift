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
/// When a TUI app is active (alternate screen or mouse reporting), both
/// overrides change behaviour:
///
/// - **Scroll**: SGR 1006 sequences (`\x1b[<64;col;rowM` / `\x1b[<65;col;rowM`)
///   are synthesised manually and written to the PTY.  SwiftTerm's own
///   ``scrollWheel`` does not reliably generate these for trackpad continuous
///   deltas, so we accumulate `scrollingDeltaY` and emit one event per line.
///
/// - **Shift+Enter**: ESC+CR (`\x1b\r`) is sent in TUI mode.
///   charmbracelet/x/input parses Kitty/modifyOtherKeys sequences correctly,
///   but OpenCode has a command-routing bug (#1505) where structural
///   Shift+Enter events fail to reach the textarea and fall through to submit.
///   ESC+CR is the Ghostty-proven workaround that bypasses the interceptor.
///   When the Kitty protocol is formally negotiated, SwiftTerm's own encoder
///   takes over instead.
final class ScrollTrackingTerminalView: LocalProcessTerminalView {

    // ----------------------------------------------------------------
    // MARK: - Scroll-tracking state
    // ----------------------------------------------------------------

    private var isTrackingScroll = false
    private var userScrollTarget: Int?

    /// Accumulates sub-line trackpad scroll deltas for TUI SGR synthesis.
    private var scrollAccumulator: CGFloat = 0

    // ----------------------------------------------------------------
    // MARK: - Init / deinit
    // ----------------------------------------------------------------

    override init(frame: CGRect) {
        Self.installOverrides()
        super.init(frame: frame)
        print("[STTV] init — self=\(ObjectIdentifier(self))")
    }

    required init?(coder: NSCoder) {
        Self.installOverrides()
        super.init(coder: coder)
        print("[STTV] init(coder:) — self=\(ObjectIdentifier(self))")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        print("[STTV] viewDidMoveToWindow — self=\(ObjectIdentifier(self)) window=\(window?.description ?? "nil")")
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        print("[STTV] viewDidMoveToSuperview — self=\(ObjectIdentifier(self)) superview=\(superview == nil ? "nil" : "present") isHidden=\(isHidden)")
    }

    // ----------------------------------------------------------------
    // MARK: - TerminalDelegate (MacTerminalView) — process-driven scroll
    // ----------------------------------------------------------------

    /// Intercepts ``Terminal.scroll()`` before the viewport updates.
    /// When the user has manually scrolled up, this prevents every
    /// line of process output from snapping `yDisp` back to the bottom.
    /// Skipped when the alternate screen is active (TUI app owns the viewport).
    override func scrolled(source terminal: Terminal, yDisp: Int) {
        if isTrackingScroll,
           let target = userScrollTarget,
           terminal.buffer.yDisp > target,
           !terminal.isCurrentBufferAlternate
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

            // When mouse reporting is active or the alternate screen is in use,
            // a TUI app (e.g. OpenCode) owns the viewport. SwiftTerm's own
            // scrollWheel does not reliably synthesize SGR sequences for
            // trackpad continuous deltas, so we do it manually: accumulate
            // sub-line deltas and write one SGR 1006 event per discrete line.
            if self.terminal.mouseMode != .off || self.terminal.isCurrentBufferAlternate {
                self.scrollAccumulator += event.scrollingDeltaY
                let lines = Int(self.scrollAccumulator)
                guard lines != 0 else { return }
                self.scrollAccumulator -= CGFloat(lines)

                let loc = self.convert(event.locationInWindow, from: nil)
                let cols = max(1, self.terminal.cols)
                let rows = max(1, self.terminal.rows)
                let cellW = self.frame.width  / CGFloat(cols)
                let cellH = self.frame.height / CGFloat(rows)
                let col = max(1, min(Int(loc.x / cellW) + 1, cols))
                let row = max(1, min(Int((self.frame.height - loc.y) / cellH) + 1, rows))

                // SGR 1006: button 64 = scroll up, 65 = scroll down.
                // scrollingDeltaY > 0 means fingers moved up → content scrolls up.
                let button = lines > 0 ? 64 : 65
                let seq = Array("\u{1b}[<\(button);\(col);\(row)M".utf8)
                if let p = self.process {
                    for _ in 0..<abs(lines) {
                        p.send(data: ArraySlice(seq))
                    }
                }
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

            NSLog("[STTV] keyDown keyCode=%d chars=%@ mods=0x%x isShiftEnter=%d",
                  event.keyCode,
                  event.characters ?? "(nil)",
                  event.modifierFlags.rawValue,
                  isShiftEnter ? 1 : 0)

            guard isShiftEnter else {
                original(self, selector, event)
                return
            }

            let kittyEmpty = self.terminal.keyboardEnhancementFlags.isEmpty
            let isAlt = self.terminal.isCurrentBufferAlternate
            let mouseOff = self.terminal.mouseMode == .off
            NSLog("[STTV] ShiftEnter: kittyEmpty=%d isAlt=%d mouseOff=%d",
                  kittyEmpty ? 1 : 0, isAlt ? 1 : 0, mouseOff ? 1 : 0)

            if isAlt || !mouseOff {
                // TUI app (e.g. OpenCode/Bubble Tea): always send ESC+CR (\x1b\r).
                // Even with Kitty active, SwiftTerm would send \x1b[13;2u which
                // OpenCode parses correctly but bug #1505 causes it to fall through
                // to submit. ESC+CR bypasses the command interceptor entirely.
                NSLog("[STTV] -> sending ESC+CR [0x1B, 0x0D] to PTY")
                self.process?.send(data: ArraySlice([0x1B, 0x0D]))
            } else if kittyEmpty {
                // Plain scrollback CLI, no Kitty: bare LF + local echo.
                NSLog("[STTV] -> sending 0x0A + local echo to PTY")
                if let p = self.process {
                    p.send(data: ArraySlice([0x0A]))
                }
                self.feed(byteArray: ArraySlice([0x0D, 0x0A]))
            } else {
                // Plain scrollback CLI with Kitty active: defer to SwiftTerm's encoder.
                NSLog("[STTV] -> deferring to original (plain CLI + Kitty)")
                original(self, selector, event)
            }
        }

        let imp = imp_implementationWithBlock(block)
        class_addMethod(ScrollTrackingTerminalView.self, selector, imp, typeEncoding)
    }
}
