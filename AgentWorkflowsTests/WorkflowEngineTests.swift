import Testing
import Foundation
@testable import AgentWorkflows

// MARK: - MockAgentEngine

/// Test double for AgentEngine that captures all interactions without PTY/terminal dependencies.
final class MockAgentEngine: AgentEngine {
    var engineState: EngineState = .idle
    var onStepComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?
    var onProcessReady: (() -> Void)?
    private(set) var injectedPrompts: [String] = []
    private(set) var startCalls: [(workingDirectory: String, tool: String)] = []
    private(set) var terminateCallCount = 0

    func start(workingDirectory: String, tool: String) throws {
        startCalls.append((workingDirectory, tool))
        engineState = .running
    }

    func injectPrompt(_ text: String) {
        injectedPrompts.append(text)
    }

    func terminate() {
        terminateCallCount += 1
        engineState = .idle
    }
}

// MARK: - FakeProcessRunner

final class FakeProcessHandle: ProcessHandle {
    func terminate() {}
    func killImmediately() {}
}

/// Synchronous ProcessRunner double. Captures the `onExit` callback from the most
/// recent `run()` call; call `simulateExit()` to fire it inline.
final class FakeProcessRunner: ProcessRunner {
    private(set) var runCount = 0
    private var pendingOnExit: ((Int32) -> Void)?

    @discardableResult
    func run(
        workingDirectory: URL,
        progressDirectory: URL,
        effort: Effort,
        onEvent: @escaping ([IterationEvent]) -> Void,
        onRawLine: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> any ProcessHandle {
        runCount += 1
        pendingOnExit = onExit
        return FakeProcessHandle()
    }

    func simulateExit(exitCode: Int32 = 0) {
        let callback = pendingOnExit
        pendingOnExit = nil
        callback?(exitCode)
    }
}

// MARK: - WorkflowEngineTests

/// Tests for the workflow execution engine — prompt injection, step completion,
/// auto-advance, pause handling, and clear handling.
struct WorkflowEngineTests {

    private let testDir: URL
    private let signalDir: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AW-Engine-Tests-\(UUID().uuidString)")
        testDir = base
        signalDir = base.appendingPathComponent("signals")
        try FileManager.default.createDirectory(at: signalDir, withIntermediateDirectories: true)
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: testDir)
    }

    // MARK: - Helpers

    private func makeSession(id: UUID = UUID()) -> Session {
        Session(
            id: id,
            name: "Test Session",
            workingDirectory: testDir.path,
            workflowName: "Test Workflow",
            state: .idle,
            currentPhaseIndex: 0,
            currentStepIndex: 0,
            completedStepIDs: []
        )
    }

    private func makeStep(
        id: String = UUID().uuidString,
        type: StepType = .prompt,
        agent: String? = nil,
        prompt: String? = "Do something"
    ) -> WorkflowStep {
        WorkflowStep(
            id: id,
            type: type,
            agent: agent,
            prompt: prompt,
            promptFile: nil
        )
    }

    private func makePhase(
        name: String = "Phase 1",
        steps: [WorkflowStep]
    ) -> Phase {
        Phase(name: name, steps: steps)
    }

    private func signalFilePath(for session: Session) -> String {
        signalDir.appendingPathComponent("step-complete-\(session.id.uuidString)").path
    }

    /// Polls until the condition is true or timeout elapses.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @Sendable () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting for condition")
    }

    // MARK: - Step Execution

    @Test func startExecutesFirstPromptStep() throws {
        let step = makeStep(prompt: "Hello, agent")
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        #expect(mock.injectedPrompts.count == 1)
        #expect(mock.injectedPrompts[0] == "Hello, agent")
        cleanup()
    }

    @Test func ralphWorkflowUsesUpdatedPlanSkillSteps() {
        let planSteps = Workflow.ralph.phases[0].steps

        #expect(planSteps.map(\.id) == [
            "plan-excavate",
            "plan-grill-with-docs",
            "plan-to-prd",
            "plan-to-tasks",
        ])
        #expect(planSteps.map(\.type) == [
            .excavate,
            .prompt,
            .prompt,
            .prompt,
        ])
        #expect(planSteps.map(\.prompt) == [
            "/excavation-agent {progress-path}",
            "/grill-with-docs",
            "/to-prd {progress-path}",
            "/to-tasks {progress-path}",
        ])
    }

    @Test func excavateStepWritesSymbolIndexBeforeDispatchingToExcavationRole() throws {
        let sourceFile = testDir.appendingPathComponent("Feature.swift")
        try """
        public final class ExcavationTarget {
            public func surface() {}
            private func hide() {}
        }
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let globalSettingsURL = testDir.appendingPathComponent("settings.json")
        let settings = Settings.default
        let excavationSettings = Settings(
            sidebarTitleProvider: settings.sidebarTitleProvider,
            planCLI: settings.planCLI,
            verifyCLI: settings.verifyCLI,
            buildCLI: settings.buildCLI,
            excavationCLI: .codex
        )
        try JSONEncoder().encode(excavationSettings).write(to: globalSettingsURL)
        let settingsStore = SettingsStore(
            appSettings: AppSettings(globalURL: globalSettingsURL, perRepoURL: nil)
        )

        let excavateStep = WorkflowStep(
            id: "plan-excavate",
            type: .excavate,
            label: "Excavate",
            agent: nil,
            prompt: "/excavation-agent {progress-path}",
            promptFile: nil
        )
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [excavateStep])])
        let session = makeSession()
        let mainEngine = MockAgentEngine()
        let excavationEngine = MockAgentEngine()
        mainEngine.engineState = .running
        excavationEngine.engineState = .running
        var resolvedRoles: [EngineManager.EngineRole] = []
        var resolvedAgents: [String?] = []

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engineResolver: { agent, role in
                resolvedRoles.append(role)
                resolvedAgents.append(agent)
                return role == .excavation ? excavationEngine : mainEngine
            },
            signalFilePath: signalFilePath(for: session),
            settingsStore: settingsStore
        )
        engine.start()

        let symbolIndexURL = SessionDirectoryLayout.symbolIndexFileURL(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: session.id
        )
        let symbolIndex = try String(contentsOf: symbolIndexURL)

        #expect(resolvedRoles == [.excavation])
        #expect(resolvedAgents == ["cli/codex"])
        #expect(mainEngine.injectedPrompts.isEmpty)
        #expect(excavationEngine.injectedPrompts.count == 1)
        #expect(excavationEngine.injectedPrompts[0].hasPrefix("$excavation-agent"))
        #expect(symbolIndex.contains("[[types]]"))
        #expect(symbolIndex.contains(#"name = "ExcavationTarget""#))
        cleanup()
    }

    @Test func codexPromptStepRewritesKnownSkillSlashCommandToSkillMention() throws {
        let step = makeStep(agent: "cli/codex", prompt: "/to-prd {progress-path}")
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        #expect(mock.injectedPrompts[0] == "$to-prd {progress-path}")
        cleanup()
    }

    @Test func piPromptStepRewritesKnownSkillSlashCommandToPiSkillCommand() throws {
        let step = makeStep(agent: "cli/pi", prompt: "/to-tasks {progress-path}")
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        #expect(mock.injectedPrompts[0] == "/skill:to-tasks {progress-path}")
        cleanup()
    }

    @Test func openCodePromptStepKeepsSlashCommand() throws {
        let step = makeStep(agent: "cli/openCode", prompt: "/grill-with-docs")
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        #expect(mock.injectedPrompts[0] == "/grill-with-docs")
        cleanup()
    }

    @Test func commandRewriteLeavesUnknownSlashTextUnchanged() throws {
        let step = makeStep(agent: "cli/codex", prompt: "/not-a-skill keep this literal")
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        #expect(mock.injectedPrompts[0] == "/not-a-skill keep this literal")
        cleanup()
    }

    @Test func startSetsExecutionStateToExecuting() throws {
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [makeStep()])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )

        #expect(engine.executionState == .idle)
        engine.start()
        #expect(engine.executionState == .executing)
        cleanup()
    }

    @Test func stepIDAddedToCompletedAfterMarkComplete() throws {
        let stepID = "step-001"
        let step = makeStep(id: stepID)
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        engine.handleStepCompletion()

        #expect(engine.completedStepIDs == [stepID])
        cleanup()
    }

    // MARK: - Step Completion (button-driven)

    @Test func handleStepCompletionAdvancesToNextStep() throws {
        let step1 = makeStep(id: "s1", prompt: "First")
        let step2 = makeStep(id: "s2", prompt: "Second")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [step1, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(mock.injectedPrompts == ["First"])

        engine.handleStepCompletion()

        #expect(mock.injectedPrompts == ["First", "Second"])
        cleanup()
    }

    // MARK: - Auto-Advance

    @Test func fullPhaseExecutesInSequence() throws {
        let steps = (1...3).map { i in makeStep(id: "s\(i)", prompt: "Step \(i)") }
        let workflow = Workflow(name: "W", phases: [makePhase(steps: steps)])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(mock.injectedPrompts == ["Step 1"])

        engine.handleStepCompletion()
        #expect(mock.injectedPrompts == ["Step 1", "Step 2"])

        engine.handleStepCompletion()
        #expect(mock.injectedPrompts == ["Step 1", "Step 2", "Step 3"])
        cleanup()
    }

    @Test func advancesToNextPhaseAfterCurrentPhaseCompletes() throws {
        let phase1Steps = [makeStep(id: "p1s1", prompt: "Phase 1 Step")]
        let phase2Steps = [makeStep(id: "p2s1", prompt: "Phase 2 Step")]
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Phase 1", steps: phase1Steps),
            makePhase(name: "Phase 2", steps: phase2Steps),
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(mock.injectedPrompts == ["Phase 1 Step"])

        engine.handleStepCompletion()

        #expect(mock.injectedPrompts == ["Phase 1 Step", "Phase 2 Step"])
        #expect(engine.currentPhaseIndex == 1)
        #expect(engine.currentStepIndex == 0)
        cleanup()
    }

    @Test func workflowCompletesAfterLastStep() throws {
        let step = makeStep(id: "only", prompt: "Only step")
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        engine.handleStepCompletion()

        #expect(engine.executionState == .completed)
        #expect(engine.completedStepIDs == ["only"])
        cleanup()
    }

    @Test func multiPhaseWorkflowCompletesAfterAllPhases() throws {
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "P1", steps: [makeStep(id: "s1", prompt: "A")]),
            makePhase(name: "P2", steps: [makeStep(id: "s2", prompt: "B")]),
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        engine.handleStepCompletion()  // complete phase 1
        engine.handleStepCompletion()  // complete phase 2

        #expect(engine.executionState == .completed)
        #expect(engine.completedStepIDs == ["s1", "s2"])
        cleanup()
    }

    // MARK: - Pause Blocks

    @Test func pauseBlockSetsStateToPaused() throws {
        let step1 = makeStep(id: "s1", prompt: "Do work")
        let pauseStep = makeStep(id: "pause1", type: .pause)
        let step2 = makeStep(id: "s2", prompt: "After pause")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [step1, pauseStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Complete step 1 → engine hits pause block
        engine.handleStepCompletion()

        #expect(engine.executionState == .paused)
        cleanup()
    }

    @Test func pauseBlockDoesNotInjectPrompt() throws {
        let step1 = makeStep(id: "s1", prompt: "Work")
        let pauseStep = makeStep(id: "pause1", type: .pause)
        let step2 = makeStep(id: "s2", prompt: "After pause")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [step1, pauseStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        engine.handleStepCompletion()

        // Only step1's prompt should have been injected — pause emits no prompt
        #expect(mock.injectedPrompts == ["Work"])
        cleanup()
    }

    @Test func continueAfterPauseResumesNextStep() throws {
        let step1 = makeStep(id: "s1", prompt: "Before")
        let pauseStep = makeStep(id: "pause1", type: .pause)
        let step2 = makeStep(id: "s2", prompt: "After")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [step1, pauseStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Complete step 1 → hits pause
        engine.handleStepCompletion()

        // Continue after pause → step 2 fires
        engine.continueExecution()

        #expect(engine.executionState == .executing)
        #expect(mock.injectedPrompts == ["Before", "After"])
        cleanup()
    }

    @Test func pauseBlockAsFirstStepPausesImmediately() throws {
        let pauseStep = makeStep(id: "pause1", type: .pause)
        let step1 = makeStep(id: "s1", prompt: "After pause")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [pauseStep, step1])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Pause is the first step — should pause immediately with no prompt injection
        #expect(engine.executionState == .paused)
        #expect(mock.injectedPrompts.isEmpty)
        cleanup()
    }

    // MARK: - Clear Blocks

    @Test func clearBlockAutoAdvancesWithoutUserAction() async throws {
        let step1 = makeStep(id: "s1", prompt: "Work")
        let clearStep = makeStep(id: "clear1", type: .restartCLI)
        let step2 = makeStep(id: "s2", prompt: "Continue")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [step1, clearStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.restartCLIAction = { _, _, _ in .success(()) }
        engine.start()

        // Complete step 1 → restart CLI action succeeds → step 2 executes
        engine.handleStepCompletion()
        try await waitUntil { mock.injectedPrompts.count >= 2 }

        // Step 2's prompt should be injected (restart CLI completes without user action)
        #expect(mock.injectedPrompts.last == "Continue")
        cleanup()
    }

    @Test func clearBlockIsTrackedInCompletedStepIDs() async throws {
        let step1 = makeStep(id: "s1", prompt: "Work")
        let clearStep = makeStep(id: "clear1", type: .restartCLI)
        let step2 = makeStep(id: "s2", prompt: "More")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [step1, clearStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.restartCLIAction = { _, _, _ in .success(()) }
        engine.start()

        engine.handleStepCompletion()
        try await waitUntil { mock.injectedPrompts.count >= 2 }

        // Restart CLI step should be in completedStepIDs after succeeding
        #expect(engine.completedStepIDs.contains("clear1"))
        cleanup()
    }

    @Test func restartCLIStepAdvancesLoopOnCoordinatorSuccess() async throws {
        let step1 = makeStep(id: "s1", prompt: "Before")
        let restartStep = makeStep(id: "restart1", type: .restartCLI)
        let step2 = makeStep(id: "s2", prompt: "After")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [step1, restartStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.restartCLIAction = { _, _, _ in .success(()) }
        engine.start()

        engine.handleStepCompletion()
        try await waitUntil { mock.injectedPrompts.count >= 2 }

        #expect(engine.completedStepIDs.contains("restart1"))
        #expect(mock.injectedPrompts.last == "After")
        cleanup()
    }

    @Test func restartCLIStepPausesOnCoordinatorFailure() async throws {
        let restartStep = makeStep(id: "restart1", type: .restartCLI)
        let step2 = makeStep(id: "s2", prompt: "Should not run")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [restartStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.restartCLIAction = { _, _, _ in .failure(.stopFailed) }
        engine.start()

        try await waitUntil { engine.executionState == .paused }

        #expect(engine.executionState == .paused)
        #expect(!engine.completedStepIDs.contains("restart1"))
        #expect(mock.injectedPrompts.isEmpty)
        cleanup()
    }

    @Test func restartCLIRetryAfterFailureViaPlay() async throws {
        let restartStep = makeStep(id: "restart1", type: .restartCLI)
        let step2 = makeStep(id: "s2", prompt: "After restart")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [restartStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        var callCount = 0
        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        // First call fails, second call succeeds
        engine.restartCLIAction = { _, _, _ in
            callCount += 1
            return callCount == 1 ? .failure(.startFailed) : .success(())
        }
        engine.start()

        // Wait for first attempt to fail and engine to pause
        try await waitUntil { engine.executionState == .paused }
        #expect(callCount == 1)
        #expect(!engine.completedStepIDs.contains("restart1"))

        // Press Play — continueExecution retries the restart step
        engine.continueExecution()

        try await waitUntil { mock.injectedPrompts.count >= 1 }
        #expect(callCount == 2)
        #expect(engine.completedStepIDs.contains("restart1"))
        #expect(mock.injectedPrompts.last == "After restart")
        cleanup()
    }

    // MARK: - Break Blocks (outside loop — auto-advance)

    @Test func breakBlockOutsideLoopAutoAdvances() throws {
        let step1 = makeStep(id: "s1", prompt: "Before")
        let breakStep = makeStep(id: "brk", type: .break_)
        let step2 = makeStep(id: "s2", prompt: "After")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [step1, breakStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        engine.handleStepCompletion()

        // Break block should auto-advance when not in a loop context
        #expect(mock.injectedPrompts == ["Before", "After"])
        cleanup()
    }

    // MARK: - Stop

    @Test func stopSetsStateToIdle() throws {
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [makeStep()])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(engine.executionState == .executing)

        engine.stop()
        #expect(engine.executionState == .idle)
        cleanup()
    }

    @Test func stopTerminatesAgentEngine() throws {
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [makeStep()])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        engine.stop()

        #expect(mock.terminateCallCount == 1)
        cleanup()
    }

    @Test func stopPreventsStepCompletion() throws {
        let step1 = makeStep(id: "s1", prompt: "Work")
        let step2 = makeStep(id: "s2", prompt: "More")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [step1, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        engine.stop()

        // handleStepCompletion after stop is a no-op — engine is not executing
        engine.handleStepCompletion()

        #expect(mock.injectedPrompts == ["Work"])
        #expect(engine.executionState == .idle)
        cleanup()
    }

    // MARK: - Resume from Incomplete Step

    @Test func resumesFromFirstIncompleteStep() throws {
        let step1 = makeStep(id: "s1", prompt: "First")
        let step2 = makeStep(id: "s2", prompt: "Second")
        let step3 = makeStep(id: "s3", prompt: "Third")
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [step1, step2, step3])
        ])
        var session = makeSession()
        session.completedStepIDs = ["s1", "s2"]
        session.currentStepIndex = 2

        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Should skip s1 and s2, inject s3 directly
        #expect(mock.injectedPrompts == ["Third"])
        cleanup()
    }

    @Test func resumesFromCorrectPhase() throws {
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "P1", steps: [makeStep(id: "s1", prompt: "Phase 1")]),
            makePhase(name: "P2", steps: [makeStep(id: "s2", prompt: "Phase 2")]),
        ])
        var session = makeSession()
        session.completedStepIDs = ["s1"]
        session.currentPhaseIndex = 1
        session.currentStepIndex = 0

        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Should start from phase 2's first step
        #expect(mock.injectedPrompts == ["Phase 2"])
        cleanup()
    }

    // MARK: - Edge Cases

    @Test func emptyWorkflowCompletesImmediately() throws {
        let workflow = Workflow(name: "Empty", phases: [])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        #expect(engine.executionState == .completed)
        #expect(mock.injectedPrompts.isEmpty)
        cleanup()
    }

    @Test func emptyPhaseIsSkipped() throws {
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Empty", steps: []),
            makePhase(name: "Real", steps: [makeStep(id: "s1", prompt: "Here")]),
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        #expect(mock.injectedPrompts == ["Here"])
        #expect(engine.currentPhaseIndex == 1)
        cleanup()
    }

    @Test func allStepsAlreadyCompletedSetsCompleted() throws {
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [makeStep(id: "s1"), makeStep(id: "s2")])
        ])
        var session = makeSession()
        session.completedStepIDs = ["s1", "s2"]

        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        #expect(engine.executionState == .completed)
        #expect(mock.injectedPrompts.isEmpty)
        cleanup()
    }

    @Test func startWhenAlreadyExecutingIsNoOp() throws {
        let step1 = makeStep(prompt: "Only once")
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step1])])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        engine.start() // Second call should be no-op

        #expect(mock.injectedPrompts.count == 1)
        cleanup()
    }

    @Test func continueWhenNotPausedIsNoOp() throws {
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [makeStep()])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        let promptCountBefore = mock.injectedPrompts.count
        engine.continueExecution() // Not paused — should be no-op
        #expect(mock.injectedPrompts.count == promptCountBefore)
        cleanup()
    }

    @Test func stopWhenIdleIsNoOp() throws {
        let workflow = Workflow(name: "W", phases: [])
        let session = makeSession()
        let mock = MockAgentEngine()

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )

        engine.stop() // Already idle — should not crash
        #expect(engine.executionState == .idle)
        #expect(mock.terminateCallCount == 0)
        cleanup()
    }

    // MARK: - Phase and Step Index Tracking

    @Test func currentStepIndexAdvancesWithinPhase() throws {
        let steps = (1...3).map { i in makeStep(id: "s\(i)", prompt: "Step \(i)") }
        let workflow = Workflow(name: "W", phases: [makePhase(steps: steps)])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(engine.currentStepIndex == 0)

        engine.handleStepCompletion()
        #expect(engine.currentStepIndex == 1)

        engine.handleStepCompletion()
        #expect(engine.currentStepIndex == 2)
        cleanup()
    }

    @Test func currentPhaseIndexAdvancesAcrossPhases() throws {
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "P1", steps: [makeStep(id: "s1", prompt: "A")]),
            makePhase(name: "P2", steps: [makeStep(id: "s2", prompt: "B")]),
            makePhase(name: "P3", steps: [makeStep(id: "s3", prompt: "C")]),
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(engine.currentPhaseIndex == 0)

        engine.handleStepCompletion()
        #expect(engine.currentPhaseIndex == 1)

        engine.handleStepCompletion()
        #expect(engine.currentPhaseIndex == 2)
        cleanup()
    }

    // MARK: - Loop/Break Steps (Linear Execution)
    //
    // Phase-level loop/iterate behavior has been removed. Loop and iterate_tasks are now
    // step-level blocks with nested children. The engine currently executes all steps
    // linearly — break steps are auto-completed, and loop/iterate_tasks container steps
    // are auto-completed without executing their nested children.
    //
    // Full loop/iterate_tasks block execution is a required engine follow-up.

    @Test func breakStepIsAutoCompletedInLinearExecution() throws {
        let step1 = makeStep(id: "s1", prompt: "Work A")
        let step2 = makeStep(id: "s2", prompt: "Work B")
        let breakStep = makeStep(id: "brk", type: .break_, prompt: nil)
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Phase", steps: [step1, breakStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(mock.injectedPrompts == ["Work A"])

        // Complete step 1 → break auto-completed → step 2 fires
        engine.handleStepCompletion()
        #expect(mock.injectedPrompts == ["Work A", "Work B"])
        #expect(engine.completedStepIDs.contains("brk"))

        engine.stop()
        cleanup()
    }

    @Test func breakWithNoSkipWhenFiresImmediatelyInLoop() throws {
        let step1 = makeStep(id: "s1", prompt: "Once")
        let breakStep = makeStep(id: "brk", type: .break_, prompt: nil)
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Loop", steps: [step1, breakStep])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Complete step 1 → break has no skip_when → fires immediately → loop exits
        engine.handleStepCompletion()

        #expect(mock.injectedPrompts == ["Once"])
        #expect(engine.executionState == .completed)
        cleanup()
    }

    @Test func loopExitsAndAdvancesToNextPhase() throws {
        let loopStep = makeStep(id: "ls1", prompt: "In loop")
        let breakStep = makeStep(id: "brk", type: .break_, prompt: nil)
        let afterStep = makeStep(id: "ns1", prompt: "After loop")
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Loop", steps: [loopStep, breakStep]),
            makePhase(name: "Next", steps: [afterStep]),
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(mock.injectedPrompts == ["In loop"])

        // Complete loop step → break fires (no skip_when) → advance to next phase
        engine.handleStepCompletion()

        #expect(mock.injectedPrompts == ["In loop", "After loop"])
        #expect(engine.currentPhaseIndex == 1)
        cleanup()
    }

    @Test func linearExecutionCompletesAfterBreakStep() throws {
        let step1 = makeStep(id: "s1", prompt: "Work")
        let breakStep = makeStep(id: "brk", type: .break_, prompt: nil)
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Phase", steps: [step1, breakStep])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(mock.injectedPrompts == ["Work"])

        // Complete step 1 → break auto-completed → workflow completes (linear)
        engine.handleStepCompletion()

        #expect(engine.executionState == .completed)
        #expect(mock.injectedPrompts == ["Work"])
        cleanup()
    }

    @Test func loopIterationCountStaysZeroInLinearExecution() throws {
        let step1 = makeStep(id: "s1", prompt: "Count me")
        let breakStep = makeStep(id: "brk", type: .break_, prompt: nil)
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Phase", steps: [step1, breakStep])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )

        #expect(engine.loopIterationCount == 0)
        engine.start()

        // Complete step 1 → break auto-completed → workflow done (no loops)
        engine.handleStepCompletion()

        #expect(engine.loopIterationCount == 0)
        cleanup()
    }

    @Test func loopIterationCountIsZeroBeforeStart() throws {
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Loop", steps: [makeStep(id: "s1")])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )

        #expect(engine.loopIterationCount == 0)
        cleanup()
    }

    @Test func breakAtStartDoesNotSkipInLinearExecution() throws {
        let breakStep = makeStep(id: "brk", type: .break_, prompt: nil)
        let nextStep = makeStep(id: "s1", prompt: "Runs after break")
        let afterStep = makeStep(id: "ns1", prompt: "After phase")
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Phase", steps: [breakStep, nextStep]),
            makePhase(name: "Next", steps: [afterStep]),
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Break auto-completed → next step fires (linear, no phase skip)
        #expect(mock.injectedPrompts == ["Runs after break"])
        #expect(engine.currentPhaseIndex == 0)
        #expect(engine.completedStepIDs.contains("brk"))
        cleanup()
    }

    @Test func breakInMiddleDoesNotSkipInLinearExecution() throws {
        let step1 = makeStep(id: "s1", prompt: "Before break")
        let breakStep = makeStep(id: "brk", type: .break_, prompt: nil)
        let step2 = makeStep(id: "s2", prompt: "After break")
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Phase", steps: [step1, breakStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Complete step 1 → break auto-completed → step 2 fires (linear, no skip)
        engine.handleStepCompletion()

        #expect(mock.injectedPrompts == ["Before break", "After break"])
        #expect(engine.completedStepIDs.contains("brk"))
        cleanup()
    }

    @Test func pauseThenBreakInLinearExecution() throws {
        let step1 = makeStep(id: "s1", prompt: "Work")
        let pauseStep = makeStep(id: "pause1", type: .pause, prompt: nil)
        let breakStep = makeStep(id: "brk", type: .break_, prompt: nil)
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Phase", steps: [step1, pauseStep, breakStep])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(mock.injectedPrompts == ["Work"])

        // Complete step 1 → hits pause
        engine.handleStepCompletion()
        #expect(engine.executionState == .paused)

        // Continue → break auto-completed → workflow completes (linear)
        engine.continueExecution()

        #expect(engine.executionState == .completed)
        #expect(engine.completedStepIDs.contains("brk"))
        cleanup()
    }

    @Test func loopWithClearBlockAutoAdvances() async throws {
        let step1 = makeStep(id: "s1", prompt: "Work")
        let clearStep = makeStep(id: "clr", type: .restartCLI, prompt: nil)
        let breakStep = makeStep(id: "brk", type: .break_, prompt: nil)
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Loop", steps: [step1, clearStep, breakStep])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.restartCLIAction = { _, _, _ in .success(()) }
        engine.start()

        // Complete step 1 → restart CLI succeeds (async) → break fires → done
        engine.handleStepCompletion()
        try await waitUntil { engine.executionState == .completed }

        #expect(mock.injectedPrompts == ["Work"])
        #expect(engine.completedStepIDs.contains("clr"))
        cleanup()
    }

    @Test func stopDuringLoopExecution() throws {
        let step1 = makeStep(id: "s1", prompt: "Loop work")
        let breakStep = makeStep(id: "brk", type: .break_, prompt: nil)
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Loop", steps: [step1, breakStep])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(engine.executionState == .executing)

        engine.stop()
        #expect(engine.executionState == .idle)
        #expect(mock.terminateCallCount == 1)
        cleanup()
    }

    // MARK: - Task Iteration (Linear Execution)
    //
    // Phase-level iterate behavior has been removed. iterate_tasks is now a step-level
    // block with nested children. The engine currently auto-completes iterate_tasks steps
    // without executing their nested children. Full iterate_tasks block execution is a
    // required engine follow-up.

    /// Task entry for writing test tasks.json files. Mirrors the production Task
    /// schema (id, category, description, acceptance_criteria, effort, passes).
    private struct TestTask: Codable {
        let id: Int
        let category: String
        let description: String
        let acceptance_criteria: [String]
        let effort: String
        var passes: Bool

        init(
            id: Int,
            description: String,
            passes: Bool,
            category: String = "schema",
            acceptance_criteria: [String] = ["stub"],
            effort: String = "low"
        ) {
            self.id = id
            self.category = category
            self.description = description
            self.acceptance_criteria = acceptance_criteria
            self.effort = effort
            self.passes = passes
        }
    }

    /// Writes a tasks.json file to the progress directory (signalDir).
    private func writeTasksFile(_ tasks: [TestTask]) throws {
        let data = try JSONEncoder().encode(tasks)
        try data.write(to: signalDir.appendingPathComponent("tasks.json"))
    }

    /// Removes the tasks.json file from the progress directory.
    private func removeTasksFile() {
        try? FileManager.default.removeItem(at: signalDir.appendingPathComponent("tasks.json"))
    }

    @Test func phaseWithPromptStepsExecutesLinearlyRegardlessOfTasks() throws {
        let step = makeStep(id: "s1", prompt: "Do task work")
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Build", steps: [step])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        // Tasks file exists but engine doesn't read it for phase-level iteration
        try writeTasksFile([
            TestTask(id: 1, description: "Task 1", passes: false),
            TestTask(id: 2, description: "Task 2", passes: false),
        ])

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(mock.injectedPrompts == ["Do task work"])

        engine.handleStepCompletion()

        #expect(engine.executionState == .completed)
        #expect(mock.injectedPrompts == ["Do task work"])
        cleanup()
    }

    @Test func iteratePhaseAdvancesToNextPhaseWhenDone() throws {
        let iterStep = makeStep(id: "is1", prompt: "Iterate work")
        let nextStep = makeStep(id: "ns1", prompt: "After iterate")
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Iterate", steps: [iterStep]),
            makePhase(name: "Next", steps: [nextStep]),
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        try writeTasksFile([
            TestTask(id: 1, description: "Task 1", passes: false),
        ])

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(mock.injectedPrompts == ["Iterate work"])

        // Complete step → advance to next phase
        try writeTasksFile([TestTask(id: 1, description: "Task 1", passes: true)])
        engine.handleStepCompletion()

        #expect(mock.injectedPrompts == ["Iterate work", "After iterate"])
        #expect(engine.currentPhaseIndex == 1)
        cleanup()
    }

    @Test func multipleStepsInPhaseExecuteLinearlyOnce() throws {
        let step1 = makeStep(id: "s1", prompt: "Step A")
        let step2 = makeStep(id: "s2", prompt: "Step B")
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Build", steps: [step1, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(mock.injectedPrompts == ["Step A"])

        engine.handleStepCompletion()
        #expect(mock.injectedPrompts == ["Step A", "Step B"])

        engine.handleStepCompletion()
        #expect(engine.executionState == .completed)
        #expect(mock.injectedPrompts == ["Step A", "Step B"])
        cleanup()
    }

    @Test func iteratePhaseSingleTaskCompletesAfterOneIteration() throws {
        let step = makeStep(id: "s1", prompt: "Single task")
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Iterate", steps: [step])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        try writeTasksFile([
            TestTask(id: 1, description: "Only task", passes: false),
        ])

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        try writeTasksFile([TestTask(id: 1, description: "Only task", passes: true)])
        engine.handleStepCompletion()

        #expect(mock.injectedPrompts == ["Single task"])
        #expect(engine.executionState == .completed)
        cleanup()
    }

    // -- Linear Execution (no phase-level skip/iterate) --

    @Test func phaseRunsNormallyEvenWhenAllTasksDone() throws {
        let step = makeStep(id: "s1", prompt: "Runs regardless")
        let afterStep = makeStep(id: "ns1", prompt: "After")
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Build", steps: [step]),
            makePhase(name: "Next", steps: [afterStep]),
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        try writeTasksFile([
            TestTask(id: 1, description: "Task 1", passes: true),
            TestTask(id: 2, description: "Task 2", passes: true),
        ])

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Phase runs its steps normally (no phase-level iteration skip)
        #expect(mock.injectedPrompts == ["Runs regardless"])
        #expect(engine.currentPhaseIndex == 0)
        cleanup()
    }

    @Test func iteratePhaseWithPauseBlockHaltsAndResumes() throws {
        let step1 = makeStep(id: "s1", prompt: "Work")
        let pauseStep = makeStep(id: "p1", type: .pause)
        let step2 = makeStep(id: "s2", prompt: "After pause")
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Iterate", steps: [step1, pauseStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        try writeTasksFile([
            TestTask(id: 1, description: "Task 1", passes: false),
        ])

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(mock.injectedPrompts == ["Work"])

        // Complete step 1 → hits pause
        engine.handleStepCompletion()
        #expect(engine.executionState == .paused)

        // Continue → step 2 fires
        engine.continueExecution()
        #expect(mock.injectedPrompts == ["Work", "After pause"])

        // Complete step 2 → all done → completed
        try writeTasksFile([TestTask(id: 1, description: "Task 1", passes: true)])
        engine.handleStepCompletion()

        #expect(engine.executionState == .completed)
        cleanup()
    }

    @Test func iteratePhaseWithClearBlockAutoAdvances() async throws {
        let step1 = makeStep(id: "s1", prompt: "Work")
        let clearStep = makeStep(id: "clr", type: .restartCLI)
        let step2 = makeStep(id: "s2", prompt: "After clear")
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Iterate", steps: [step1, clearStep, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        try writeTasksFile([
            TestTask(id: 1, description: "Task 1", passes: false),
        ])

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.restartCLIAction = { _, _, _ in .success(()) }
        engine.start()
        #expect(mock.injectedPrompts == ["Work"])

        // Complete step 1 → restart CLI succeeds (async) → step 2 fires
        engine.handleStepCompletion()
        try await waitUntil { mock.injectedPrompts.count >= 2 }
        #expect(mock.injectedPrompts == ["Work", "After clear"])
        #expect(engine.completedStepIDs.contains("clr"))

        // Complete step 2 → all done → completed
        try writeTasksFile([TestTask(id: 1, description: "Task 1", passes: true)])
        engine.handleStepCompletion()

        #expect(engine.executionState == .completed)
        cleanup()
    }

    // -- Validation & Control --

    @Test func completedStepIDsAccumulateInLinearExecution() throws {
        let step1 = makeStep(id: "s1", prompt: "Step A")
        let step2 = makeStep(id: "s2", prompt: "Step B")
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Build", steps: [step1, step2])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Complete step 1 → step 2 fires
        engine.handleStepCompletion()

        // Step 1 is in completedStepIDs, step 2 is not yet
        #expect(engine.completedStepIDs.contains("s1"))
        #expect(!engine.completedStepIDs.contains("s2"))

        engine.stop()
        cleanup()
    }

    @Test func loopStepWithEmptyChildrenFailsValidation() throws {
        let loopStep = WorkflowStep(
            id: "loop1", type: .loop, agent: nil, prompt: nil, promptFile: nil, steps: []
        )
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Build", steps: [loopStep])
        ])

        #expect(throws: WorkflowValidationError.self) {
            try workflow.validate()
        }
    }

    // MARK: - IterateTasks Step Delegation

    @Test func iterateTasksStepStartsHeadlessRalphDriver() throws {
        let fakeRunner = FakeProcessRunner()
        let mock = MockAgentEngine()
        mock.engineState = .running
        let step = WorkflowStep(id: "iter", type: .iterateTasks, agent: nil, prompt: nil, promptFile: nil, maxIterations: 5)
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()

        try writeTasksFile([TestTask(id: 1, description: "T1", passes: false)])
        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engineResolver: { _, _ in mock },
            signalFilePath: signalFilePath(for: session),
            processRunner: fakeRunner
        )
        engine.start()

        // HeadlessRalphDriver started — subprocess spawned via FakeProcessRunner
        #expect(fakeRunner.runCount == 1)
        // Step is NOT auto-completed; engine holds and waits
        #expect(!engine.completedStepIDs.contains(step.id))
        #expect(engine.executionState == .executing)
        #expect(engine.activeLoopDriver != nil)
        cleanup()
    }

    @Test func loopDriverCompletionMarksStepDoneAndAdvances() throws {
        let fakeRunner = FakeProcessRunner()
        let mock = MockAgentEngine()
        mock.engineState = .running
        let iterStep = WorkflowStep(id: "iter-step", type: .iterateTasks, agent: nil, prompt: nil, promptFile: nil, maxIterations: 5)
        let nextStep = makeStep(id: "next-step", prompt: "Next work")
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [iterStep, nextStep])])
        let session = makeSession()

        // All tasks pass — driver should complete after one exit
        try writeTasksFile([TestTask(id: 1, description: "T1", passes: true)])
        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engineResolver: { _, _ in mock },
            signalFilePath: signalFilePath(for: session),
            processRunner: fakeRunner
        )
        engine.start()
        #expect(fakeRunner.runCount == 1)

        fakeRunner.simulateExit()  // all-pass → HeadlessRalphDriver completes

        #expect(engine.completedStepIDs.contains("iter-step"))
        #expect(engine.activeLoopDriver == nil)
        // Workflow advanced — next step's prompt injected into mock engine
        #expect(mock.injectedPrompts.count == 1)
        #expect(mock.injectedPrompts[0].contains("Next work"))
        cleanup()
    }

    @Test func loopDriverStalledSetsExecutionStateToStalled() throws {
        let fakeRunner = FakeProcessRunner()
        let mock = MockAgentEngine()
        mock.engineState = .running
        let step = WorkflowStep(id: "iter", type: .iterateTasks, agent: nil, prompt: nil, promptFile: nil, maxIterations: 25)
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()

        // No progress — passes stays [false] across all iterations
        try writeTasksFile([TestTask(id: 1, description: "T1", passes: false)])
        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engineResolver: { _, _ in mock },
            signalFilePath: signalFilePath(for: session),
            processRunner: fakeRunner
        )
        engine.start()

        fakeRunner.simulateExit()  // iteration 1 — stallCount 1
        #expect(engine.executionState == .executing)
        fakeRunner.simulateExit()  // iteration 2 — stallCount 2
        #expect(engine.executionState == .executing)
        fakeRunner.simulateExit()  // iteration 3 — stallCount 3 → stalled
        #expect(engine.executionState == .stalled)
        #expect(engine.activeLoopDriver == nil)
        cleanup()
    }

    @Test func continueFromStalledReentersLoopWithFreshBudget() throws {
        let fakeRunner = FakeProcessRunner()
        let mock = MockAgentEngine()
        mock.engineState = .running
        let step = WorkflowStep(id: "iter", type: .iterateTasks, agent: nil, prompt: nil, promptFile: nil, maxIterations: 25)
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()

        try writeTasksFile([TestTask(id: 1, description: "T1", passes: false)])
        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engineResolver: { _, _ in mock },
            signalFilePath: signalFilePath(for: session),
            processRunner: fakeRunner
        )
        engine.start()

        fakeRunner.simulateExit()  // iteration 1 — stallCount 1
        fakeRunner.simulateExit()  // iteration 2 — stallCount 2
        fakeRunner.simulateExit()  // iteration 3 — stallCount 3 → stalled
        #expect(engine.executionState == .stalled)
        #expect(engine.activeLoopDriver == nil)

        let runCountAtStall = fakeRunner.runCount

        // Continue re-enters with a fresh HeadlessRalphDriver — new subprocess spawned
        engine.continueExecution()

        #expect(engine.executionState == .executing)
        #expect(engine.activeLoopDriver != nil)
        #expect(fakeRunner.runCount == runCountAtStall + 1,
                "continuing from stalled starts a new Iteration")
        cleanup()
    }

    @Test func stopHaltsLoopDriverAndClearsActiveDriver() throws {
        let fakeRunner = FakeProcessRunner()
        let mock = MockAgentEngine()
        mock.engineState = .running
        let step = WorkflowStep(id: "iter", type: .iterateTasks, agent: nil, prompt: nil, promptFile: nil, maxIterations: 25)
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()

        try writeTasksFile([TestTask(id: 1, description: "T1", passes: false)])
        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engineResolver: { _, _ in mock },
            signalFilePath: signalFilePath(for: session),
            processRunner: fakeRunner
        )
        engine.start()
        #expect(engine.executionState == .executing)

        let runCountBeforeStop = fakeRunner.runCount
        engine.stop()

        #expect(engine.executionState == .idle)
        #expect(engine.activeLoopDriver == nil)
        // Exit after stop must not re-spawn
        fakeRunner.simulateExit()
        #expect(fakeRunner.runCount == runCountBeforeStop, "no re-spawn after stop")
        cleanup()
    }

    // MARK: - Run From Here (Mid-Run)

    @Test func runFromStepDuringExecutionDoesNotTerminateAgent() throws {
        let step = makeStep(id: "s1", prompt: "Work")
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engineResolver: { _, _ in mock },
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(engine.executionState == .executing)

        engine.runFromStep(phaseIndex: 0, stepIndex: 0)

        #expect(mock.terminateCallCount == 0)
        cleanup()
    }

    @Test func runFromStepDuringExecutionRedispatchesPrompt() throws {
        let step = makeStep(id: "s1", prompt: "Step 1")
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step])])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engineResolver: { _, _ in mock },
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(engine.executionState == .executing)
        #expect(mock.injectedPrompts.count == 1)

        engine.runFromStep(phaseIndex: 0, stepIndex: 0)

        #expect(mock.injectedPrompts.count == 2)
        #expect(mock.injectedPrompts.allSatisfy { $0 == "Step 1" })
        cleanup()
    }

    @Test func runFromStepDuringExecutionClearsCompletionsFromTarget() throws {
        let step1 = makeStep(id: "s1", prompt: "Step 1")
        let step2 = makeStep(id: "s2", prompt: "Step 2")
        let step3 = makeStep(id: "s3", prompt: "Step 3")
        let workflow = Workflow(name: "W", phases: [makePhase(steps: [step1, step2, step3])])
        var session = makeSession()
        session.completedStepIDs = ["s1"]
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engineResolver: { _, _ in mock },
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(engine.executionState == .executing)

        engine.runFromStep(phaseIndex: 0, stepIndex: 0)

        #expect(!engine.completedStepIDs.contains("s1"))
        #expect(!engine.completedStepIDs.contains("s2"))
        #expect(!engine.completedStepIDs.contains("s3"))
        #expect(engine.currentPhaseIndex == 0)
        #expect(engine.currentStepIndex == 0)
        cleanup()
    }

    @Test func stopDuringIteratePhase() throws {
        let step = makeStep(id: "s1", prompt: "Iterate work")
        let workflow = Workflow(name: "W", phases: [
            makePhase(name: "Iterate", steps: [step])
        ])
        let session = makeSession()
        let mock = MockAgentEngine()
        mock.engineState = .running

        try writeTasksFile([
            TestTask(id: 1, description: "Task 1", passes: false),
        ])

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()
        #expect(engine.executionState == .executing)

        engine.stop()
        #expect(engine.executionState == .idle)
        #expect(mock.terminateCallCount == 1)
        cleanup()
    }
}
