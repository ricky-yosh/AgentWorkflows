import Foundation
import Testing
import SwiftUI
@testable import AgentWorkflows

@MainActor
@Suite("TerminalDividerState")
struct TerminalDividerStateTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "terminal-divider-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Default Width

    @Test("default width is 320pt when no persisted value exists")
    func defaultWidth() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        #expect(state.width == 320)
        #expect(state.collapsed == false)
    }

    // MARK: - Collapse

    @Test("collapse sets width to 0 and marks collapsed")
    func collapseSetsWidthToZero() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.collapse()

        #expect(state.width == 0)
        #expect(state.collapsed == true)
    }

    @Test("collapse is idempotent when already collapsed")
    func collapseIdempotent() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.collapse()
        state.collapse()

        #expect(state.width == 0)
        #expect(state.collapsed == true)
    }

    // MARK: - Expand

    @Test("expand restores width before collapse")
    func expandRestoresPreviousWidth() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.collapse()
        state.expand()

        #expect(state.width == 320)
        #expect(state.collapsed == false)
    }

    @Test("expand restores custom width after drag")
    func expandRestoresCustomWidth() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.handleDrag(delta: 100, windowWidth: 1200)
        let draggedWidth = state.width
        state.collapse()
        state.expand()

        #expect(state.width == draggedWidth)
        #expect(state.collapsed == false)
    }

    @Test("expand is idempotent when already expanded")
    func expandIdempotent() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.collapse()
        state.expand()
        state.expand()

        #expect(state.width == 320)
        #expect(state.collapsed == false)
    }

    // MARK: - Toggle

    @Test("toggle collapses when expanded")
    func toggleCollapses() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.toggle()

        #expect(state.width == 0)
        #expect(state.collapsed == true)
    }

    @Test("toggle expands when collapsed")
    func toggleExpands() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.collapse()
        state.toggle()

        #expect(state.width == 320)
        #expect(state.collapsed == false)
    }

    // MARK: - Drag Clamping

    @Test("drag below 200pt clamps to 200pt")
    func dragClampsToMinimum() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.handleDrag(delta: -200, windowWidth: 1200)

        #expect(state.width == 200)
    }

    @Test("drag above 60 percent of window width clamps to 60 percent")
    func dragClampsToMaximum() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.handleDrag(delta: 2000, windowWidth: 1200)

        #expect(state.width == 720) // 1200 * 0.6
    }

    @Test("drag within bounds applies delta")
    func dragWithinBounds() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.handleDrag(delta: 80, windowWidth: 1200)

        #expect(state.width == 400) // 320 + 80
    }

    @Test("drag is ignored when collapsed")
    func dragIgnoredWhenCollapsed() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.collapse()
        state.handleDrag(delta: 100, windowWidth: 1200)

        #expect(state.width == 0)
        #expect(state.collapsed == true)
    }

    @Test("negative drag reduces width")
    func negativeDragReducesWidth() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.handleDrag(delta: -50, windowWidth: 1200)

        #expect(state.width == 270) // 320 - 50
    }

    // MARK: - Persistence

    @Test("collapsed state persists to UserDefaults")
    func collapsedStatePersists() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.collapse()

        let restored = TerminalDividerState(defaults: defaults)
        #expect(restored.collapsed == true)
        #expect(restored.width == 0)
    }

    @Test("width persists to UserDefaults after drag")
    func widthPersistsAfterDrag() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.handleDrag(delta: 50, windowWidth: 1200)
        let currentWidth = state.width

        let restored = TerminalDividerState(defaults: defaults)
        #expect(restored.collapsed == false)
        #expect(restored.width == currentWidth)
    }

    @Test("expand restores persisted pre-collapse width")
    func expandRestoresPersistedPreCollapseWidth() {
        let defaults = makeDefaults()
        let state = TerminalDividerState(defaults: defaults)

        state.handleDrag(delta: 80, windowWidth: 1200)
        let draggedWidth = state.width
        state.collapse()

        let restored = TerminalDividerState(defaults: defaults)
        restored.expand()

        #expect(restored.width == draggedWidth)
    }
}
