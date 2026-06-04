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
/// - **Shift+Enter**: CSI u (`\x1b[13;2u`) is sent in TUI mode by default,
///   which crossterm (Ratatui, Codex) and other modern TUI libraries parse
///   as Shift+Enter.  The sequence is sent when the Kitty keyboard protocol
///   is negotiated, the alternate screen is active, or mouse reporting is on.
///   OpenCode overrides `tuiShiftEnterBytes` to ESC+CR (`\x1b\r`) to bypass
///   charmbracelet/x/input command-routing bug #1505.
final class ScrollTrackingTerminalView: LocalProcessTerminalView {

    // ----------------------------------------------------------------
    // MARK: - Scroll-tracking state
    // ----------------------------------------------------------------

    private var isTrackingScroll = false
    private var userScrollTarget: Int?

    /// Accumulates sub-line trackpad scroll deltas for TUI SGR synthesis.
    private var scrollAccumulator: CGFloat = 0

    /// Byte sequence sent on Shift+Enter when a TUI app is active (Kitty
    /// protocol negotiated, alternate screen, or mouse reporting).  Defaults
    /// to CSI u (`ESC [ 13 ; 2 u`), which crossterm parses as Shift+Enter.
    /// OpenCode overrides this to ESC+CR to work around a charmbracelet/x/input
    /// command-routing bug (#1505).
    var tuiShiftEnterBytes: [UInt8] = [0x1B, 0x5B, 0x31, 0x33, 0x3B, 0x32, 0x75]

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
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

            guard isShiftEnter else {
                original(self, selector, event)
                return
            }

            let kittyEmpty = self.terminal.keyboardEnhancementFlags.isEmpty
            let isAlt = self.terminal.isCurrentBufferAlternate
            let mouseOff = self.terminal.mouseMode == .off
            let bytes = self.tuiShiftEnterBytes

            NSLog("[keyDown] Shift+Enter detected | isAlt=%d mouseOff=%d kittyEmpty=%d | sending %d bytes: %@",
                  isAlt ? 1 : 0, mouseOff ? 1 : 0, kittyEmpty ? 1 : 0,
                  bytes.count,
                  bytes.map { String(format: "%02x", $0) }.joined(separator: " "))

            if !kittyEmpty || isAlt || !mouseOff {
                // TUI or Kitty mode — send the tool-specific byte sequence to PTY.
                NSLog("[keyDown] → sending %d bytes to PTY", bytes.count)
                self.process?.send(data: ArraySlice(bytes))
            } else {
                NSLog("[keyDown] → normal path: sending LF (0x0A) to PTY")
                if let p = self.process {
                    p.send(data: ArraySlice([0x0A]))
                }
                self.feed(byteArray: ArraySlice([0x0D, 0x0A]))
            }
        }

        let imp = imp_implementationWithBlock(block)
        class_addMethod(ScrollTrackingTerminalView.self, selector, imp, typeEncoding)
    }
}
