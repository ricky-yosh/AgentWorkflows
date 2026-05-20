import AppKit
import SwiftTerm

/// A `LocalProcessTerminalView` that signals the terminal engine when the user
/// is actively scrolling, preventing new output from snapping the viewport
/// back to the bottom.
///
/// SwiftTerm's ``Terminal/userScrolling`` flag is the engine-level gate that
/// controls auto-scroll, but the built-in ``scrollWheel(with:)`` never sets it.
/// The result is that every linefeed from a running CLI agent immediately resets
/// `yDisp = yBase`, making it impossible to scroll up and read output while a
/// process is producing new lines.
///
/// This subclass overrides ``scrollWheel(with:)`` to set `terminal.userScrolling`
/// during active scroll gestures and clear it on a short cooldown after the
/// gesture ends (including momentum). It also immediately clears the flag when
/// the user scrolls back to the very bottom, so auto-scroll resumes the moment
/// the viewport reaches the latest output.
final class ScrollTrackingTerminalView: LocalProcessTerminalView {

    /// Cooldown work item that clears `terminal.userScrolling` after the
    /// scroll gesture fully ends (finger lift + momentum decay).
    private var scrollEndWorkItem: DispatchWorkItem?

    override func scrollWheel(with event: NSEvent) {
        guard event.deltaY != 0 else { return }

        scrollEndWorkItem?.cancel()
        scrollEndWorkItem = nil

        terminal.userScrolling = true

        super.scrollWheel(with: event)

        // If the user scrolled all the way to the bottom (or the viewport
        // naturally reached yBase), re-enable auto-scroll immediately.
        if terminal.displayBuffer.yDisp == terminal.displayBuffer.yBase {
            terminal.userScrolling = false
            return
        }

        // Schedule a clear once the full gesture (finger + momentum) ends.
        // Trackpad events go through: phase .began→.changed→.ended,
        // then momentumPhase .began→.changed→.ended.
        // Mouse wheel events have phase .none & momentumPhase .none per tick.
        let gestureEnded = event.phase == .ended || event.phase == .cancelled
        let momentumEnded = event.momentumPhase == .ended || event.momentumPhase == .cancelled
        let noMomentum = event.momentumPhase == .none
        let isMouseWheel = event.phase == .none && event.momentumPhase == .none

        if (gestureEnded && (momentumEnded || noMomentum)) || momentumEnded || isMouseWheel {
            scheduleClear()
        }
    }

    private func scheduleClear() {
        let work = DispatchWorkItem { [weak self] in
            self?.terminal.userScrolling = false
        }
        scrollEndWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
