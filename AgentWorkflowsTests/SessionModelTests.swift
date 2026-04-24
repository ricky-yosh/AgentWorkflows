import Testing
import Foundation
import SwiftUI
@testable import AgentWorkflows

// MARK: - SessionState Tests

struct SessionStateTests {

    @Test func allCasesExist() {
        #expect(SessionState.allCases.count == 5)
        #expect(SessionState.allCases.contains(.idle))
        #expect(SessionState.allCases.contains(.running))
        #expect(SessionState.allCases.contains(.paused))
        #expect(SessionState.allCases.contains(.completed))
        #expect(SessionState.allCases.contains(.stalled))
    }

    @Test func codableRoundTrip() throws {
        for state in SessionState.allCases {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(SessionState.self, from: data)
            #expect(decoded == state)
        }
    }

    @Test func decodesFromJSONString() throws {
        let json = Data(#""idle""#.utf8)
        let state = try JSONDecoder().decode(SessionState.self, from: json)
        #expect(state == .idle)
    }
}

// MARK: - Session State Projection Tests

struct SessionStateProjectionTests {

    @Test("label projection covers all 5 states with expected values")
    func labelProjection() {
        let expected: [(SessionState, String)] = [
            (.idle, "idle"),
            (.running, "running"),
            (.paused, "paused"),
            (.completed, "completed"),
            (.stalled, "stalled"),
        ]
        for (state, label) in expected {
            #expect(state.displayLabel == label)
        }
    }

    @Test("symbol projection covers all 5 states with expected SF symbol names")
    func symbolProjection() {
        let expected: [(SessionState, String)] = [
            (.idle, "circle"),
            (.running, "play.fill"),
            (.paused, "pause.fill"),
            (.completed, "checkmark.circle.fill"),
            (.stalled, "exclamationmark.triangle.fill"),
        ]
        for (state, symbol) in expected {
            #expect(state.symbolName == symbol)
        }
    }

    @Test("color projection is callable for all states (exhaustiveness compiler-checked)")
    func colorProjectionTotal() {
        // The switch in SessionState.color is exhaustive by compiler guarantee.
        // This test documents intent and catches any future state added without
        // a corresponding color entry.
        for state in SessionState.allCases {
            _ = state.color
        }
        #expect(SessionState.allCases.count == 5)
    }
}

// MARK: - Session Model Tests

struct SessionModelTests {

    private func makeSampleSession() -> Session {
        Session(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!,
            name: "Test Session",
            workingDirectory: "/tmp/test-project",
            workflowName: "AW Greenfield",
            state: .idle,
            currentPhaseIndex: 0,
            currentStepIndex: 0,
            completedStepIDs: []
        )
    }

    @Test func initSetsAllFields() {
        let id = UUID()
        let session = Session(
            id: id,
            name: "My Session",
            workingDirectory: "/Users/test/project",
            workflowName: "AW Greenfield",
            state: .idle,
            currentPhaseIndex: 0,
            currentStepIndex: 0,
            completedStepIDs: []
        )
        #expect(session.id == id)
        #expect(session.name == "My Session")
        #expect(session.workingDirectory == "/Users/test/project")
        #expect(session.workflowName == "AW Greenfield")
        #expect(session.state == .idle)
        #expect(session.currentPhaseIndex == 0)
        #expect(session.currentStepIndex == 0)
        #expect(session.completedStepIDs.isEmpty)
    }

    @Test func codableRoundTrip() throws {
        var session = makeSampleSession()
        session.state = .running
        session.currentPhaseIndex = 2
        session.currentStepIndex = 3
        session.completedStepIDs = ["step-1", "step-2", "step-3"]

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)

        #expect(decoded.id == session.id)
        #expect(decoded.name == session.name)
        #expect(decoded.workingDirectory == session.workingDirectory)
        #expect(decoded.workflowName == session.workflowName)
        #expect(decoded.state == .running)
        #expect(decoded.currentPhaseIndex == 2)
        #expect(decoded.currentStepIndex == 3)
        #expect(decoded.completedStepIDs == ["step-1", "step-2", "step-3"])
    }

    @Test func encodesToValidJSON() throws {
        let session = makeSampleSession()
        let data = try JSONEncoder().encode(session)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["name"] as? String == "Test Session")
        #expect(json?["workingDirectory"] as? String == "/tmp/test-project")
        #expect(json?["workflowName"] as? String == "AW Greenfield")
    }

    @Test func completedStepIDsPreservesOrder() throws {
        var session = makeSampleSession()
        session.completedStepIDs = ["c", "a", "b"]

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        #expect(decoded.completedStepIDs == ["c", "a", "b"])
    }

    @Test func manuallyTitledDefaultsFalseOnNewSession() {
        let session = makeSampleSession()
        #expect(session.manuallyTitled == false)
    }

    @Test func manuallyTitledRoundTrip() throws {
        var session = makeSampleSession()
        session.manuallyTitled = true
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        #expect(decoded.manuallyTitled == true)
    }

    @Test func manuallyTitledDefaultsFalseOnLegacyJSON() throws {
        // Simulate a state.json written before manuallyTitled existed.
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789ABC",
          "name": "Old Session",
          "workingDirectory": "/tmp/old",
          "workflowName": "AW Greenfield",
          "state": "idle",
          "currentPhaseIndex": 0,
          "currentStepIndex": 0,
          "completedStepIDs": []
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Session.self, from: json)
        #expect(decoded.manuallyTitled == false)
    }
}

// MARK: - Seed Gating Tests

/// Documents the sentinel step ID that gates the pre-Play seed prompt.
/// SessionDetailView.play shows the seed sheet iff completedStepIDs does
/// NOT contain "plan-grill-me", so these tests pin that invariant.
struct SeedGatingTests {

    private func makeSession(completedStepIDs: [String] = []) -> Session {
        Session(
            id: UUID(),
            name: "Test",
            workingDirectory: "/tmp",
            workflowName: "Ralph",
            state: .idle,
            currentPhaseIndex: 0,
            currentStepIndex: 0,
            completedStepIDs: completedStepIDs
        )
    }

    @Test("fresh session has no completedStepIDs — seed sheet should be shown")
    func freshSessionNeedsSeed() {
        let session = makeSession()
        #expect(!session.completedStepIDs.contains("plan-grill-me"))
    }

    @Test("session with plan-grill-me completed — seed sheet should be skipped")
    func grillMeCompletedSkipsSeed() {
        let session = makeSession(completedStepIDs: ["plan-grill-me"])
        #expect(session.completedStepIDs.contains("plan-grill-me"))
    }

    @Test("other completed steps do not satisfy the gating condition")
    func otherCompletedStepsDoNotSatisfyGate() {
        let session = makeSession(completedStepIDs: ["plan-ubiquitous-language", "plan-to-prd"])
        #expect(!session.completedStepIDs.contains("plan-grill-me"))
    }
}

// MARK: - Workflow Model Tests

struct WorkflowModelTests {

    @Test func workflowHasNameAndPhases() {
        let workflow = Workflow(name: "Test Workflow", phases: [])
        #expect(workflow.name == "Test Workflow")
        #expect(workflow.phases.isEmpty)
    }

    @Test func phaseHasAllFields() {
        let step = WorkflowStep(
            id: "step-1",
            type: .prompt,
            agent: "cli/claude",
            prompt: "Do something",
            promptFile: nil
        )
        let phase = Phase(
            name: "Setup",
            steps: [step]
        )
        #expect(phase.name == "Setup")
        #expect(phase.steps.count == 1)
    }

    @Test func phaseIsPurelyOrganizational() {
        let phase = Phase(name: "Build", steps: [])
        #expect(phase.name == "Build")
        #expect(phase.steps.isEmpty)
    }

    @Test func workflowStepTypes() {
        let types: [StepType] = [.prompt, .restartCLI, .pause, .break_, .comment, .loop, .iterateTasks]
        #expect(types.count == 7)
    }

    @Test func workflowStepWithPrompt() {
        let step = WorkflowStep(
            id: "step-1",
            type: .prompt,
            agent: "cli/claude",
            prompt: "Build the thing",
            promptFile: nil
        )
        #expect(step.id == "step-1")
        #expect(step.type == .prompt)
        #expect(step.agent == "cli/claude")
        #expect(step.prompt == "Build the thing")
        #expect(step.promptFile == nil)
    }

    @Test func workflowStepWithPromptFile() {
        let step = WorkflowStep(
            id: "step-2",
            type: .prompt,
            agent: "cli/claude",
            prompt: nil,
            promptFile: "aw-create-spec.md",
        )
        #expect(step.prompt == nil)
        #expect(step.promptFile == "aw-create-spec.md")
    }

    @Test func workflowCodableRoundTrip() throws {
        let step = WorkflowStep(
            id: "step-1",
            type: .prompt,
            agent: "cli/claude",
            prompt: "Hello",
            promptFile: nil
        )
        let phase = Phase(
            name: "Phase 1",
            steps: [step]
        )
        let workflow = Workflow(name: "Test", phases: [phase])

        let data = try JSONEncoder().encode(workflow)
        let decoded = try JSONDecoder().decode(Workflow.self, from: data)

        #expect(decoded.name == "Test")
        #expect(decoded.phases.count == 1)
        #expect(decoded.phases[0].name == "Phase 1")
        #expect(decoded.phases[0].steps.count == 1)
        #expect(decoded.phases[0].steps[0].id == "step-1")
        #expect(decoded.phases[0].steps[0].type == .prompt)
        #expect(decoded.phases[0].steps[0].agent == "cli/claude")
        #expect(decoded.phases[0].steps[0].prompt == "Hello")
    }

}
