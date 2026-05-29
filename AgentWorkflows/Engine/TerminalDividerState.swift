import Foundation
import Observation
import SwiftUI

/// State model for the draggable vertical divider between the terminal pane
/// and the tab pane. Manages collapse/expand, drag clamping, and persistence.
@Observable
@MainActor
final class TerminalDividerState {
    static let defaultWidth: CGFloat = 320
    static let minimumWidth: CGFloat = 200
    static let maxWindowFraction: CGFloat = 0.6

    private static let widthKey = "TerminalDividerState.width"
    private static let collapsedKey = "TerminalDividerState.collapsed"
    private static let previousWidthKey = "TerminalDividerState.previousWidth"

    private let defaults: UserDefaults

    /// The current terminal pane width. 0 when collapsed.
    private(set) var width: CGFloat

    /// Whether the terminal pane is currently collapsed.
    private(set) var collapsed: Bool

    /// Stores the width before collapse so it can be restored on expand.
    private var previousWidth: CGFloat

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedWidth = defaults.object(forKey: Self.widthKey) as? CGFloat
        let storedCollapsed = defaults.object(forKey: Self.collapsedKey) as? Bool ?? false
        let storedPrevious = defaults.object(forKey: Self.previousWidthKey) as? CGFloat

        if storedCollapsed {
            self.collapsed = true
            self.width = 0
            self.previousWidth = storedPrevious ?? storedWidth ?? Self.defaultWidth
        } else {
            self.collapsed = false
            let w = storedWidth ?? Self.defaultWidth
            self.width = w
            self.previousWidth = storedPrevious ?? w
        }
    }

    /// Collapse the terminal pane, preserving the current width for later restore.
    func collapse() {
        guard !collapsed else { return }
        previousWidth = width
        width = 0
        collapsed = true
        persist()
    }

    /// Expand the terminal pane to the width before collapse.
    func expand() {
        guard collapsed else { return }
        width = previousWidth
        collapsed = false
        persist()
    }

    /// Toggle between collapsed and expanded states.
    func toggle() {
        if collapsed {
            expand()
        } else {
            collapse()
        }
    }

    /// Apply a horizontal drag delta, clamping to minimum and maximum bounds.
    ///
    /// - Parameters:
    ///   - delta: The horizontal drag offset in points (positive = rightward).
    ///   - windowWidth: The current window width, used to compute the 60% cap.
    func handleDrag(delta: CGFloat, windowWidth: CGFloat) {
        guard !collapsed else { return }
        let clamped = clampWidth(width + delta, windowWidth: windowWidth)
        width = clamped
        persist()
    }

    /// Clamp a candidate width to the allowed range.
    private func clampWidth(_ candidate: CGFloat, windowWidth: CGFloat) -> CGFloat {
        let maxAllowed = windowWidth * Self.maxWindowFraction
        return max(Self.minimumWidth, min(candidate, maxAllowed))
    }

    private func persist() {
        defaults.set(Double(width), forKey: Self.widthKey)
        defaults.set(collapsed, forKey: Self.collapsedKey)
        defaults.set(Double(previousWidth), forKey: Self.previousWidthKey)
    }
}
