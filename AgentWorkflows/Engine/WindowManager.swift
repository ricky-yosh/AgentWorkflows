import AppKit
import Observation

@Observable
final class WindowManager {
    /// Maps session UUID → NSWindow.windowNumber for windows currently showing that session.
    private(set) var sessionWindows: [UUID: Int] = [:]

    /// Register that a window is now showing a specific session.
    func register(sessionID: UUID, windowNumber: Int) {
        // Remove any prior mapping for this window number (it may have been showing a different session)
        sessionWindows = sessionWindows.filter { $0.value != windowNumber }
        sessionWindows[sessionID] = windowNumber
    }

    /// Unregister any session mapped to this window number.
    func unregister(windowNumber: Int) {
        sessionWindows = sessionWindows.filter { $0.value != windowNumber }
    }

    /// Returns the window number for a session if it's currently open, or nil.
    /// Validates the window still exists to self-heal stale entries.
    func windowNumber(for sessionID: UUID) -> Int? {
        guard let wn = sessionWindows[sessionID] else { return nil }
        if NSApp.windows.contains(where: { $0.windowNumber == wn && $0.isVisible }) {
            return wn
        }
        // Stale entry — clean up
        sessionWindows[sessionID] = nil
        return nil
    }

    /// Focus the window showing the given session. Returns true if found and focused.
    @discardableResult
    func focusWindow(for sessionID: UUID) -> Bool {
        guard let wn = windowNumber(for: sessionID),
              let window = NSApp.windows.first(where: { $0.windowNumber == wn }) else {
            return false
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }
}
