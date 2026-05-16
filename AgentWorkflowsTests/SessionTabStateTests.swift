import Foundation
import Testing
@testable import AgentWorkflows

@Suite("SessionTabState")
struct SessionTabStateTests {

    @Test func defaultsToTerminal() {
        let state = SessionTabState()
        let sessionID = UUID()

        #expect(state.selectedTab(for: sessionID) == .terminal)
    }

    @Test func storesWorkbenchSelection() {
        let state = SessionTabState()
        let sessionID = UUID()

        state.setSelectedTab(.workbench, for: sessionID)

        #expect(state.selectedTab(for: sessionID) == .workbench)
    }
}
