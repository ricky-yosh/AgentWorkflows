import Testing
import Foundation
@testable import AgentWorkflows

struct PhaseDisplayTests {

    private let workflow = Workflow(name: "ralph", phases: [
        Phase(name: "Plan", steps: []),
        Phase(name: "Build", steps: []),
        Phase(name: "Verify", steps: []),
    ])

    private func session(state: SessionState, phaseIndex: Int = 0) -> Session {
        Session(
            id: UUID(),
            name: "test",
            workingDirectory: "/tmp",
            workflowName: "ralph",
            state: state,
            currentPhaseIndex: phaseIndex,
            currentStepIndex: 0,
            completedStepIDs: []
        )
    }

    // MARK: - Active states return phase name

    @Test func runningSessionReturnsPlanName() {
        let name = currentPhaseName(session: session(state: .running, phaseIndex: 0), workflow: workflow)
        #expect(name == "Plan")
    }

    @Test func runningSessionReturnsBuildName() {
        let name = currentPhaseName(session: session(state: .running, phaseIndex: 1), workflow: workflow)
        #expect(name == "Build")
    }

    @Test func runningSessionReturnsVerifyName() {
        let name = currentPhaseName(session: session(state: .running, phaseIndex: 2), workflow: workflow)
        #expect(name == "Verify")
    }

    @Test func pausedSessionReturnsPhaseName() {
        let name = currentPhaseName(session: session(state: .paused, phaseIndex: 1), workflow: workflow)
        #expect(name == "Build")
    }

    // MARK: - Inactive states return nil

    @Test func idleSessionReturnsNil() {
        let name = currentPhaseName(session: session(state: .idle), workflow: workflow)
        #expect(name == nil)
    }

    @Test func completedSessionReturnsNil() {
        let name = currentPhaseName(session: session(state: .completed), workflow: workflow)
        #expect(name == nil)
    }

    @Test func stalledSessionReturnsNil() {
        let name = currentPhaseName(session: session(state: .stalled), workflow: workflow)
        #expect(name == nil)
    }

    // MARK: - Out-of-range index returns nil

    @Test func outOfRangeIndexReturnsNil() {
        let name = currentPhaseName(session: session(state: .running, phaseIndex: 99), workflow: workflow)
        #expect(name == nil)
    }

    @Test func negativeIndexReturnsNil() {
        let name = currentPhaseName(session: session(state: .running, phaseIndex: -1), workflow: workflow)
        #expect(name == nil)
    }
}
