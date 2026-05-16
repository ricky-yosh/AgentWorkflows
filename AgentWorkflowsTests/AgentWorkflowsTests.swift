//
//  AgentWorkflowsTests.swift
//  AgentWorkflowsTests
//
//  Created by Richard Yoshioka on 4/8/26.
//

import Testing
import Foundation
@testable import AgentWorkflows

struct AgentWorkflowsTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func engineManagerSeparatesRolesByCompositeKey() {
        let manager = EngineManager()
        let sessionID = UUID()

        let mainEngine = manager.engine(for: sessionID, role: .main, tool: "cli/claude")
        let excavationEngine = manager.engine(for: sessionID, role: .excavation, tool: "cli/pi")

        #expect(mainEngine !== excavationEngine)
        #expect(manager.existingEngine(for: sessionID, tool: "cli/claude") === mainEngine)
        #expect(manager.existingEngine(for: sessionID, role: .excavation, tool: "cli/pi") === excavationEngine)
        #expect(manager.activeTools(for: sessionID) == ["cli/claude"])
        #expect(manager.activeTools(for: sessionID, role: .excavation) == ["cli/pi"])
    }

}
