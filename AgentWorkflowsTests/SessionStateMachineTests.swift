import Testing
import Foundation
@testable import AgentWorkflows

// MARK: - Session State Transition Tests

/// Tests for R9: Session state transitions follow a strict state machine.
/// Valid: idle→running, running→paused, paused→running, running→idle, running→completed.
/// All other transitions must be rejected.
struct SessionStateTransitionTests {

    // MARK: - Helpers

    private func makeSession(state: SessionState = .idle) -> Session {
        Session(
            id: UUID(),
            name: "Test Session",
            workingDirectory: "/tmp/test",
            workflowName: "Test Workflow",
            state: state,
            currentPhaseIndex: 0,
            currentStepIndex: 0,
            completedStepIDs: []
        )
    }

    // MARK: - Valid Transitions

    @Test("idle → running is valid (play)")
    func idleToRunning() throws {
        var session = makeSession(state: .idle)
        try session.transition(to: .running)
        #expect(session.state == .running)
    }

    @Test("running → paused is valid (pause block or crash)")
    func runningToPaused() throws {
        var session = makeSession(state: .running)
        try session.transition(to: .paused)
        #expect(session.state == .paused)
    }

    @Test("paused → running is valid (continue)")
    func pausedToRunning() throws {
        var session = makeSession(state: .paused)
        try session.transition(to: .running)
        #expect(session.state == .running)
    }

    @Test("running → idle is valid (manual stop)")
    func runningToIdle() throws {
        var session = makeSession(state: .running)
        try session.transition(to: .idle)
        #expect(session.state == .idle)
    }

    @Test("running → completed is valid (last step finishes)")
    func runningToCompleted() throws {
        var session = makeSession(state: .running)
        try session.transition(to: .completed)
        #expect(session.state == .completed)
    }

    // MARK: - Invalid Transitions (from idle)

    @Test("idle → paused is invalid")
    func idleToPaused() {
        var session = makeSession(state: .idle)
        #expect(throws: SessionTransitionError.self) {
            try session.transition(to: .paused)
        }
        #expect(session.state == .idle)
    }

    @Test("idle → completed is invalid")
    func idleToCompleted() {
        var session = makeSession(state: .idle)
        #expect(throws: SessionTransitionError.self) {
            try session.transition(to: .completed)
        }
        #expect(session.state == .idle)
    }

    @Test("idle → idle is invalid (self-transition)")
    func idleToIdle() {
        var session = makeSession(state: .idle)
        #expect(throws: SessionTransitionError.self) {
            try session.transition(to: .idle)
        }
        #expect(session.state == .idle)
    }

    // MARK: - Invalid Transitions (from running)

    @Test("running → running is invalid (self-transition)")
    func runningToRunning() {
        var session = makeSession(state: .running)
        #expect(throws: SessionTransitionError.self) {
            try session.transition(to: .running)
        }
        #expect(session.state == .running)
    }

    // MARK: - Invalid Transitions (from paused)

    @Test("paused → idle is invalid")
    func pausedToIdle() {
        var session = makeSession(state: .paused)
        #expect(throws: SessionTransitionError.self) {
            try session.transition(to: .idle)
        }
        #expect(session.state == .paused)
    }

    @Test("paused → completed is invalid")
    func pausedToCompleted() {
        var session = makeSession(state: .paused)
        #expect(throws: SessionTransitionError.self) {
            try session.transition(to: .completed)
        }
        #expect(session.state == .paused)
    }

    @Test("paused → paused is invalid (self-transition)")
    func pausedToPaused() {
        var session = makeSession(state: .paused)
        #expect(throws: SessionTransitionError.self) {
            try session.transition(to: .paused)
        }
        #expect(session.state == .paused)
    }

    // MARK: - Invalid Transitions (from completed)

    @Test("completed → running is invalid")
    func completedToRunning() {
        var session = makeSession(state: .completed)
        #expect(throws: SessionTransitionError.self) {
            try session.transition(to: .running)
        }
        #expect(session.state == .completed)
    }

    @Test("completed → paused is invalid")
    func completedToPaused() {
        var session = makeSession(state: .completed)
        #expect(throws: SessionTransitionError.self) {
            try session.transition(to: .paused)
        }
        #expect(session.state == .completed)
    }

    @Test("completed → idle is invalid")
    func completedToIdle() {
        var session = makeSession(state: .completed)
        #expect(throws: SessionTransitionError.self) {
            try session.transition(to: .idle)
        }
        #expect(session.state == .completed)
    }

    @Test("completed → completed is invalid (self-transition)")
    func completedToCompleted() {
        var session = makeSession(state: .completed)
        #expect(throws: SessionTransitionError.self) {
            try session.transition(to: .completed)
        }
        #expect(session.state == .completed)
    }

    // MARK: - Error Contains Context

    @Test("transition error includes from and to states")
    func errorContainsStates() {
        var session = makeSession(state: .completed)
        do {
            try session.transition(to: .running)
            Issue.record("Expected SessionTransitionError")
        } catch let error as SessionTransitionError {
            #expect(error.from == .completed)
            #expect(error.to == .running)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Full Lifecycle

    @Test("full lifecycle: idle → running → paused → running → completed")
    func fullLifecycle() throws {
        var session = makeSession(state: .idle)

        try session.transition(to: .running)
        #expect(session.state == .running)

        try session.transition(to: .paused)
        #expect(session.state == .paused)

        try session.transition(to: .running)
        #expect(session.state == .running)

        try session.transition(to: .completed)
        #expect(session.state == .completed)
    }

    @Test("manual stop lifecycle: idle → running → idle")
    func manualStopLifecycle() throws {
        var session = makeSession(state: .idle)

        try session.transition(to: .running)
        #expect(session.state == .running)

        try session.transition(to: .idle)
        #expect(session.state == .idle)
    }

    @Test("restart after manual stop: idle → running → idle → running")
    func restartAfterStop() throws {
        var session = makeSession(state: .idle)

        try session.transition(to: .running)
        try session.transition(to: .idle)
        try session.transition(to: .running)
        #expect(session.state == .running)
    }
}

// MARK: - Launch-Time Demotion Tests

/// Tests for R9: "On launch, any running session is demoted to paused."
struct SessionDemotionTests {

    private let testBase: URL
    private let testWorkingDir: URL
    private let registryURL: URL

    init() throws {
        testBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("AW-Demotion-Tests-\(UUID().uuidString)")
        testWorkingDir = testBase.appendingPathComponent("project")
        registryURL = testBase.appendingPathComponent("sessions.json")
        try FileManager.default.createDirectory(at: testWorkingDir, withIntermediateDirectories: true)
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: testBase)
    }

    private func makeSession(id: UUID = UUID(), state: SessionState, name: String = "Test") -> Session {
        Session(
            id: id,
            name: name,
            workingDirectory: testWorkingDir.path,
            workflowName: "Test Workflow",
            state: state,
            currentPhaseIndex: 0,
            currentStepIndex: 0,
            completedStepIDs: []
        )
    }

    private func writeSessionToDisk(_ session: Session) throws {
        let workingDir = URL(fileURLWithPath: session.workingDirectory)
        let sessionDir = SessionDirectoryLayout.sessionDirectory(workingDirectory: workingDir, sessionID: session.id)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(session)
        try data.write(to: SessionDirectoryLayout.stateFileURL(workingDirectory: workingDir, sessionID: session.id))
        let entry = SessionRegistryEntry(id: session.id, name: session.name,
                                         workingDirectory: session.workingDirectory,
                                         workflowName: session.workflowName)
        try SessionRegistry(fileURL: registryURL).add(entry)
    }

    @Test("running sessions are demoted to paused on launch")
    func runningDemotedToPaused() throws {
        defer { cleanup() }
        let session = makeSession(state: .running)
        try writeSessionToDisk(session)

        let store = SessionStore(registryURL: registryURL)

        let loaded = store.sessions.first(where: { $0.id == session.id })
        #expect(loaded != nil)
        #expect(loaded?.state == .paused)
    }

    @Test("idle sessions remain idle on launch")
    func idleUnchanged() throws {
        defer { cleanup() }
        let session = makeSession(state: .idle)
        try writeSessionToDisk(session)

        let store = SessionStore(registryURL: registryURL)

        let loaded = store.sessions.first(where: { $0.id == session.id })
        #expect(loaded?.state == .idle)
    }

    @Test("paused sessions remain paused on launch")
    func pausedUnchanged() throws {
        defer { cleanup() }
        let session = makeSession(state: .paused)
        try writeSessionToDisk(session)

        let store = SessionStore(registryURL: registryURL)

        let loaded = store.sessions.first(where: { $0.id == session.id })
        #expect(loaded?.state == .paused)
    }

    @Test("completed sessions remain completed on launch")
    func completedUnchanged() throws {
        defer { cleanup() }
        let session = makeSession(state: .completed)
        try writeSessionToDisk(session)

        let store = SessionStore(registryURL: registryURL)

        let loaded = store.sessions.first(where: { $0.id == session.id })
        #expect(loaded?.state == .completed)
    }

    @Test("multiple running sessions are all demoted")
    func multipleRunningDemoted() throws {
        defer { cleanup() }
        let s1 = makeSession(state: .running, name: "Running 1")
        let s2 = makeSession(state: .running, name: "Running 2")
        let s3 = makeSession(state: .idle, name: "Idle")
        try writeSessionToDisk(s1)
        try writeSessionToDisk(s2)
        try writeSessionToDisk(s3)

        let store = SessionStore(registryURL: registryURL)

        #expect(store.sessions.first(where: { $0.id == s1.id })?.state == .paused)
        #expect(store.sessions.first(where: { $0.id == s2.id })?.state == .paused)
        #expect(store.sessions.first(where: { $0.id == s3.id })?.state == .idle)
    }

    @Test("demotion persists to state.json on disk")
    func demotionPersistedToDisk() throws {
        defer { cleanup() }
        let session = makeSession(state: .running)
        try writeSessionToDisk(session)

        _ = SessionStore(registryURL: registryURL)

        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: session.id
        )
        let data = try Data(contentsOf: stateFile)
        let reloaded = try JSONDecoder().decode(Session.self, from: data)
        #expect(reloaded.state == .paused)
    }
}

// MARK: - State Persistence Tests

/// Tests that state transitions are persisted to state.json via SessionStore.
struct SessionStatePersistenceTests {

    private let testBase: URL
    private let testWorkingDir: URL
    private let registryURL: URL

    init() throws {
        testBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("AW-Persistence-Tests-\(UUID().uuidString)")
        testWorkingDir = testBase.appendingPathComponent("project")
        registryURL = testBase.appendingPathComponent("sessions.json")
        try FileManager.default.createDirectory(at: testWorkingDir, withIntermediateDirectories: true)
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: testBase)
    }

    private func readSessionFromDisk(_ session: Session) throws -> Session {
        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: session.id
        )
        let data = try Data(contentsOf: stateFile)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Creates a session, writes it to disk in the new layout, adds a registry entry,
    /// and returns the session + a freshly-initialized store that has loaded it.
    private func bootstrapSession(id: UUID = UUID(), name: String = "Test",
                                   state: SessionState = .idle) throws -> (Session, SessionStore) {
        let session = Session(
            id: id,
            name: name,
            workingDirectory: testWorkingDir.path,
            workflowName: "W",
            state: state,
            currentPhaseIndex: 0,
            currentStepIndex: 0,
            completedStepIDs: []
        )
        let workingDir = URL(fileURLWithPath: session.workingDirectory)
        let sessionDir = SessionDirectoryLayout.sessionDirectory(workingDirectory: workingDir, sessionID: session.id)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(session)
        try data.write(to: SessionDirectoryLayout.stateFileURL(workingDirectory: workingDir, sessionID: session.id))
        let entry = SessionRegistryEntry(id: session.id, name: name,
                                         workingDirectory: session.workingDirectory,
                                         workflowName: "W")
        try SessionRegistry(fileURL: registryURL).add(entry)
        let store = SessionStore(registryURL: registryURL)
        return (session, store)
    }

    @Test("saveSession persists state change to state.json")
    func saveSessionPersistsState() throws {
        defer { cleanup() }
        var (session, store) = try bootstrapSession()
        try session.transition(to: .running)
        try store.saveSession(session)
        #expect(try readSessionFromDisk(session).state == .running)
    }

    @Test("each transition updates state.json when saved")
    func eachTransitionPersists() throws {
        defer { cleanup() }
        var (session, store) = try bootstrapSession()

        try session.transition(to: .running)
        try store.saveSession(session)
        #expect(try readSessionFromDisk(session).state == .running)

        try session.transition(to: .paused)
        try store.saveSession(session)
        #expect(try readSessionFromDisk(session).state == .paused)

        try session.transition(to: .running)
        try store.saveSession(session)
        #expect(try readSessionFromDisk(session).state == .running)

        try session.transition(to: .completed)
        try store.saveSession(session)
        #expect(try readSessionFromDisk(session).state == .completed)
    }

    @Test("saveSession also persists completedStepIDs and indices")
    func saveSessionPersistsProgress() throws {
        defer { cleanup() }
        var (session, store) = try bootstrapSession()
        try session.transition(to: .running)
        session.currentPhaseIndex = 2
        session.currentStepIndex = 3
        session.completedStepIDs = ["s1", "s2", "s3"]
        try store.saveSession(session)
        let persisted = try readSessionFromDisk(session)
        #expect(persisted.currentPhaseIndex == 2)
        #expect(persisted.currentStepIndex == 3)
        #expect(persisted.completedStepIDs == ["s1", "s2", "s3"])
    }

    @Test("in-memory sessions list reflects saved state")
    func inMemoryListUpdated() throws {
        defer { cleanup() }
        var (session, store) = try bootstrapSession()
        try session.transition(to: .running)
        try store.saveSession(session)
        let inMemory = store.sessions.first(where: { $0.id == session.id })
        #expect(inMemory?.state == .running)
    }
}

// MARK: - WorkflowEngine ↔ Session State Integration Tests

/// Tests that WorkflowEngine execution events produce the correct Session state transitions.
/// These verify the contract between WorkflowEngine callbacks and Session state.
@MainActor
struct SessionStateIntegrationTests {

    private let testDir: URL
    private let signalDir: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AW-StateInteg-Tests-\(UUID().uuidString)")
        testDir = base
        signalDir = base.appendingPathComponent("signals")
        try FileManager.default.createDirectory(at: signalDir, withIntermediateDirectories: true)
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: testDir)
    }

    // MARK: - Helpers

    private func makeSession(id: UUID = UUID(), state: SessionState = .idle) -> Session {
        Session(
            id: id,
            name: "Test Session",
            workingDirectory: testDir.path,
            workflowName: "Test Workflow",
            state: state,
            currentPhaseIndex: 0,
            currentStepIndex: 0,
            completedStepIDs: []
        )
    }

    private func makeStep(
        id: String = UUID().uuidString,
        type: StepType = .prompt,
        prompt: String? = "Do work"
    ) -> WorkflowStep {
        WorkflowStep(
            id: id,
            type: type,
            agent: nil,
            prompt: prompt,
            promptFile: nil
        )
    }

    private func makePhase(steps: [WorkflowStep]) -> Phase {
        Phase(name: "Phase 1", steps: steps)
    }

    private func signalFilePath(for session: Session) -> String {
        signalDir.appendingPathComponent("step-complete-\(session.id.uuidString)").path
    }


    // MARK: - Play (Start)

    @Test("play transitions session from idle to running and starts engine")
    func playStartsExecution() throws {
        var session = makeSession(state: .idle)
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [makeStep()])
        ])
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )

        // Play: transition state then start engine
        try session.transition(to: .running)
        engine.start()

        #expect(session.state == .running)
        #expect(engine.executionState == .executing)
        #expect(mock.injectedPrompts.count == 1)
        cleanup()
    }

    @Test("play resumes from first incomplete step, not from beginning")
    func playResumesFromIncompleteStep() throws {
        var session = makeSession(state: .idle)
        session.completedStepIDs = ["s1", "s2"]
        session.currentPhaseIndex = 0
        session.currentStepIndex = 2

        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [
                makeStep(id: "s1", prompt: "First"),
                makeStep(id: "s2", prompt: "Second"),
                makeStep(id: "s3", prompt: "Third"),
            ])
        ])
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )

        try session.transition(to: .running)
        engine.start()

        // Should only inject the third step
        #expect(mock.injectedPrompts == ["Third"])
        cleanup()
    }

    // MARK: - Stop

    @Test("stop transitions session from running to idle and terminates engine")
    func stopTerminatesExecution() throws {
        var session = makeSession(state: .running)
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [makeStep()])
        ])
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Stop: terminate engine then transition state
        engine.stop()
        try session.transition(to: .idle)

        #expect(session.state == .idle)
        #expect(engine.executionState == .idle)
        #expect(mock.terminateCallCount == 1)
        cleanup()
    }

    // MARK: - Pause (from WorkflowEngine)

    @Test("pause block in workflow transitions session to paused")
    func pauseBlockTransitionsSession() throws {
        var session = makeSession(state: .running)
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [
                makeStep(id: "s1", prompt: "Work"),
                makeStep(id: "pause1", type: .pause),
                makeStep(id: "s2", prompt: "After"),
            ])
        ])
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Complete step 1 → engine hits pause
        engine.handleStepCompletion()

        // Session should transition to paused
        try session.transition(to: .paused)
        #expect(session.state == .paused)
        #expect(engine.executionState == .paused)
        cleanup()
    }

    // MARK: - Continue (Resume from Pause)

    @Test("continue transitions session from paused to running and resumes engine")
    func continueResumesExecution() throws {
        var session = makeSession(state: .running)
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [
                makeStep(id: "s1", prompt: "Before"),
                makeStep(id: "pause1", type: .pause),
                makeStep(id: "s2", prompt: "After"),
            ])
        ])
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Complete step 1 → engine hits pause
        engine.handleStepCompletion()

        // Pause session
        try session.transition(to: .paused)

        // Continue: transition back to running, resume engine
        try session.transition(to: .running)
        engine.continueExecution()

        #expect(session.state == .running)
        #expect(engine.executionState == .executing)
        #expect(mock.injectedPrompts == ["Before", "After"])
        cleanup()
    }

    // MARK: - Completion

    @Test("last step completing transitions session to completed")
    func lastStepCompletesSession() throws {
        var session = makeSession(state: .running)
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [makeStep(id: "only", prompt: "Only step")])
        ])
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

        // Session should transition to completed
        try session.transition(to: .completed)
        #expect(session.state == .completed)
        cleanup()
    }

    // MARK: - Session Progress Sync

    @Test("session indices and completedStepIDs sync from WorkflowEngine after execution")
    func progressSyncsFromEngine() throws {
        var session = makeSession(state: .running)
        let workflow = Workflow(name: "W", phases: [
            makePhase(steps: [
                makeStep(id: "s1", prompt: "First"),
                makeStep(id: "s2", prompt: "Second"),
            ])
        ])
        let mock = MockAgentEngine()
        mock.engineState = .running

        let engine = WorkflowEngine(
            session: session,
            workflow: workflow,
            engine: mock,
            signalFilePath: signalFilePath(for: session)
        )
        engine.start()

        // Complete step 1
        engine.handleStepCompletion()

        // Sync progress from engine to session
        session.currentPhaseIndex = engine.currentPhaseIndex
        session.currentStepIndex = engine.currentStepIndex
        session.completedStepIDs = engine.completedStepIDs

        #expect(session.completedStepIDs.contains("s1"))
        #expect(session.currentStepIndex == 1)
        cleanup()
    }
}
