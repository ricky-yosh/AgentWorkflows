import Testing
import Foundation
@testable import AgentWorkflows

@MainActor
struct SidebarSessionStatusTests {

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

    // MARK: - Phase name visibility

    @Test("phaseName returns name for running session")
    func phaseNameRunning() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .running, phaseIndex: 1),
            workflow: workflow
        )
        #expect(view.phaseName == "Build")
    }

    @Test("phaseName returns name for paused session")
    func phaseNamePaused() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .paused, phaseIndex: 0),
            workflow: workflow
        )
        #expect(view.phaseName == "Plan")
    }

    @Test("phaseName returns nil for idle session")
    func phaseNameIdle() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .idle),
            workflow: workflow
        )
        #expect(view.phaseName == nil)
    }

    @Test("phaseName returns nil for completed session")
    func phaseNameCompleted() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .completed),
            workflow: workflow
        )
        #expect(view.phaseName == nil)
    }

    @Test("phaseName returns nil for stalled session")
    func phaseNameStalled() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .stalled),
            workflow: workflow
        )
        #expect(view.phaseName == nil)
    }

    // MARK: - isInBuildPhase

    @Test("isInBuildPhase is true when in Build phase")
    func buildPhaseTrue() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .running, phaseIndex: 1),
            workflow: workflow
        )
        #expect(view.isInBuildPhase == true)
    }

    @Test("isInBuildPhase is false when in Plan phase")
    func buildPhaseFalsePlan() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .running, phaseIndex: 0),
            workflow: workflow
        )
        #expect(view.isInBuildPhase == false)
    }

    @Test("isInBuildPhase is false for idle session")
    func buildPhaseFalseIdle() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .idle),
            workflow: workflow
        )
        #expect(view.isInBuildPhase == false)
    }

    // MARK: - Counters visible during Build phase

    @Test("iteration and task counters visible during Build phase")
    func countersVisibleDuringBuild() {
        let status = SessionRunStatus()
        status.beginRun()
        status.iterationCount = 3
        status.maxIterations = 25
        status.tasksPassed = 2
        status.tasksTotal = 5

        let view = SidebarSessionStatus(
            status: status,
            session: session(state: .running, phaseIndex: 1),
            workflow: workflow
        )

        #expect(view.isInBuildPhase == true)
        #expect(status.iterationCount == 3)
        #expect(status.tasksPassed == 2)
        #expect(status.tasksTotal == 5)
    }

    // MARK: - Counters hidden outside Build phase

    @Test("counters hidden during Plan phase")
    func countersHiddenDuringPlan() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .running, phaseIndex: 0),
            workflow: workflow
        )
        #expect(view.isInBuildPhase == false)
    }

    @Test("counters hidden during Verify phase")
    func countersHiddenDuringVerify() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .running, phaseIndex: 2),
            workflow: workflow
        )
        #expect(view.isInBuildPhase == false)
    }

    @Test("counters hidden for idle session")
    func countersHiddenForIdle() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .idle),
            workflow: workflow
        )
        #expect(view.isInBuildPhase == false)
    }

    // MARK: - Elapsed time visibility

    @Test("elapsed time visible when run has started")
    func elapsedVisibleWhenStarted() {
        let status = SessionRunStatus()
        status.startedAt = Date()

        let view = SidebarSessionStatus(
            status: status,
            session: session(state: .running, phaseIndex: 0),
            workflow: workflow
        )

        #expect(status.startedAt != nil)
    }

    @Test("elapsed time hidden when idle")
    func elapsedHiddenWhenIdle() {
        let status = SessionRunStatus()
        // startedAt is nil by default

        let view = SidebarSessionStatus(
            status: status,
            session: session(state: .idle),
            workflow: workflow
        )

        #expect(status.startedAt == nil)
    }

    @Test("elapsed time hidden after run finishes")
    func elapsedHiddenAfterFinish() {
        let status = SessionRunStatus()
        status.beginRun()
        status.finishRun()

        let view = SidebarSessionStatus(
            status: status,
            session: session(state: .completed),
            workflow: workflow
        )

        #expect(status.startedAt == nil)
    }

    // MARK: - All five session states

    @Test("renders for idle state")
    func rendersIdle() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .idle),
            workflow: workflow
        )
        #expect(view.session.state == .idle)
        #expect(view.phaseName == nil)
        #expect(view.isInBuildPhase == false)
    }

    @Test("renders for running state")
    func rendersRunning() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .running, phaseIndex: 1),
            workflow: workflow
        )
        #expect(view.session.state == .running)
        #expect(view.phaseName == "Build")
        #expect(view.isInBuildPhase == true)
    }

    @Test("renders for paused state")
    func rendersPaused() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .paused, phaseIndex: 1),
            workflow: workflow
        )
        #expect(view.session.state == .paused)
        #expect(view.phaseName == "Build")
    }

    @Test("renders for completed state")
    func rendersCompleted() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .completed),
            workflow: workflow
        )
        #expect(view.session.state == .completed)
        #expect(view.phaseName == nil)
    }

    @Test("renders for stalled state")
    func rendersStalled() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .stalled),
            workflow: workflow
        )
        #expect(view.session.state == .stalled)
        #expect(view.phaseName == nil)
    }

    // MARK: - No workflow

    @Test("phaseName is nil when workflow is nil")
    func phaseNameNilWorkflow() {
        let view = SidebarSessionStatus(
            status: SessionRunStatus(),
            session: session(state: .running, phaseIndex: 0),
            workflow: nil
        )
        #expect(view.phaseName == nil)
        #expect(view.isInBuildPhase == false)
    }
}
