import Foundation
import Observation

nonisolated enum ExecutionState: Equatable {
    case idle
    case executing
    case paused
    case stalled
    case completed
}

/// An event emitted by the workflow engine while executing. Rendered by
/// `ExecutionLogView`. Intentionally small — this is not full telemetry,
/// just enough context for a user to see why a step is doing what it's
/// doing.
struct ExecutionEvent: Identifiable, Equatable, Codable {
    enum Kind: String, Codable {
        case stepStarted      // a step entered execution
        case promptSent       // a prompt was injected into an engine
        case stepCompleted    // a step finished (auto-advance or signal)
        case paused           // explicit pause
        case crashed          // harness process exited unexpectedly
        case skipped          // step was skipped (skip_when / manual)
        case completed        // whole workflow finished
    }

    var id: UUID = UUID()
    let timestamp: Date
    let kind: Kind
    let message: String

    private enum CodingKeys: String, CodingKey { case timestamp, kind, message }
}

typealias RestartCLIAction = (any AgentEngine, String, String) async -> Result<Void, TerminalRestartError>

@Observable
final class WorkflowEngine {
    private(set) var executionState: ExecutionState = .idle
    private(set) var currentPhaseIndex: Int
    private(set) var currentStepIndex: Int
    private(set) var completedStepIDs: [String]
    private(set) var loopIterationCount: Int = 0

    /// Injectable override for the restartCLI step. Defaults to TerminalRestartCoordinator.
    /// Set on tests (or by EngineManager) to inject a fake or pre-configured action.
    var restartCLIAction: RestartCLIAction?

    /// Non-nil when paused due to a restartCLI failure. Identifies the step to retry
    /// rather than skip when continueExecution is called.
    private var pendingRestartStepID: String?
    /// Capped event log. Trimmed to `maxEventCount` most-recent entries to
    /// bound memory on long-running sessions.
    private(set) var events: [ExecutionEvent] = []
    private let maxEventCount = 200

    /// On-disk append-only JSONL log. Survives engine teardown so the Log
    /// tab can show history after a relaunch. Written next to the signal
    /// file in the session's progress directory.
    private var eventsFileURL: URL {
        let dir = (signalFilePath as NSString).deletingLastPathComponent
        return URL(fileURLWithPath: dir).appendingPathComponent("events.jsonl")
    }

    private func record(_ kind: ExecutionEvent.Kind, _ message: String) {
        let event = ExecutionEvent(timestamp: Date(), kind: kind, message: message)
        events.append(event)
        if events.count > maxEventCount {
            events.removeFirst(events.count - maxEventCount)
        }
        appendEventToDisk(event)
    }

    private func appendEventToDisk(_ event: ExecutionEvent) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(event) else { return }
        line.append(0x0A)  // "\n"
        let url = eventsFileURL
        let fm = FileManager.default
        try? fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }

    private func loadEventsFromDisk() {
        guard let data = try? Data(contentsOf: eventsFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [ExecutionEvent] = []
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            if let ev = try? decoder.decode(ExecutionEvent.self, from: Data(line)) {
                loaded.append(ev)
            }
        }
        if loaded.count > maxEventCount {
            loaded.removeFirst(loaded.count - maxEventCount)
        }
        events = loaded
    }

    private let session: Session
    private let workflow: Workflow
    private let engineResolver: (String?) -> AgentEngine
    private var activeEngine: AgentEngine?
    private(set) var activeLoopDriver: HeadlessRalphDriver?
    private let settingsStore: SettingsStore?
    /// Test-only override: when set, the iterate_tasks step uses this runner
    /// instead of resolving one from SettingsStore via ProcessRunnerFactory.
    private let processRunnerOverride: (any ProcessRunner)?
    private let signalFilePath: String
    private let promptDispatcher: PromptDispatcher

    /// Live status surface set by `EngineManager` after creation so
    /// `iterate_tasks` can forward events to the UI without `WorkflowEngine`
    /// needing a reference to `EngineManager`.
    weak var sessionRunStatus: SessionRunStatus?

    /// One-shot text prepended to the next prompt-step injection. Used by
    /// the pre-Play seed prompt to inject a user-supplied intent alongside
    /// the first slash command (e.g. "\(seed)\n/grill-me"). Self-clears
    /// after a single use so later steps inject unmodified.
    private var pendingSeed: String?

    /// Arms `pendingSeed` so the next prompt step prepends `seed` to its
    /// injected text. Call before `start()` to seed the first Plan step.
    func seedNextPrompt(_ seed: String) {
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSeed = trimmed.isEmpty ? nil : trimmed
    }

    /// Creates a workflow engine with an engine resolver that maps agent fields to harnesses.
    /// The resolver receives the step's `agent` field (e.g. "cli/claude") and returns the
    /// appropriate AgentEngine. A nil agent falls back to the resolver's default.
    init(
        session: Session,
        workflow: Workflow,
        engineResolver: @escaping (String?) -> AgentEngine,
        signalFilePath: String,
        settingsStore: SettingsStore? = nil,
        processRunner: (any ProcessRunner)? = nil,
        signalWatcher: SignalWatcher? = nil
    ) {
        self.session = session
        self.workflow = workflow
        self.engineResolver = engineResolver
        self.signalFilePath = signalFilePath
        self.currentPhaseIndex = session.currentPhaseIndex
        self.currentStepIndex = session.currentStepIndex
        self.completedStepIDs = session.completedStepIDs
        self.settingsStore = settingsStore
        self.processRunnerOverride = processRunner
        let watcher = signalWatcher ?? DispatchSourceSignalWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)
        self.promptDispatcher = dispatcher
        // All stored properties initialized; safe to capture self.
        dispatcher.onSignalFired = { [weak self] in
            self?.handleStepCompletion()
        }
        loadEventsFromDisk()
    }

    /// Backward-compatible initializer that wraps a single engine.
    convenience init(session: Session, workflow: Workflow, engine: AgentEngine, signalFilePath: String) {
        self.init(
            session: session,
            workflow: workflow,
            engineResolver: { _ in engine },
            signalFilePath: signalFilePath
        )
    }

    // MARK: - Public Methods

    func start() {
        guard executionState != .executing else { return }

        let hasIncompleteSteps = findNextIncompleteStep(fromPhase: currentPhaseIndex, stepIndex: currentStepIndex) != nil

        guard hasIncompleteSteps else {
            executionState = .completed
            return
        }

        executionState = .executing
        advanceLoop()
    }

    func continueExecution() {
        if executionState == .paused {
            let currentStep = workflow.phases[currentPhaseIndex].steps[currentStepIndex]
            if currentStep.id == pendingRestartStepID {
                // Paused on restartCLI failure — retry the step rather than skip it.
                pendingRestartStepID = nil
            } else {
                completedStepIDs.append(currentStep.id)
            }
            executionState = .executing
            advanceLoop()
        } else if executionState == .stalled {
            executionState = .executing
            advanceLoop()
        }
    }

    func skipCurrentStep() {
        guard executionState == .paused || executionState == .executing else { return }
        promptDispatcher.cancelWatcher()
        activeLoopDriver?.stop()
        activeLoopDriver = nil
        pendingRestartStepID = nil
        let step = workflow.phases[currentPhaseIndex].steps[currentStepIndex]
        if !completedStepIDs.contains(step.id) {
            completedStepIDs.append(step.id)
        }
        executionState = .executing
        advanceLoop()
    }

    /// Called when the harness process exits unexpectedly while a step is executing.
    /// Stops the signal watcher and transitions to paused so the UI can show the crash banner.
    func handleProcessCrash() {
        guard executionState == .executing else { return }
        promptDispatcher.cancelWatcher()
        activeLoopDriver?.stop()
        activeLoopDriver = nil
        activeEngine?.onStepComplete = nil  // process gone — don't expect step completion
        activeEngine?.onProcessExit = nil
        executionState = .paused
        record(.crashed, "Harness process exited unexpectedly")
    }

    func stop() {
        guard executionState != .idle else { return }
        promptDispatcher.cancelWatcher()
        activeLoopDriver?.stop()
        activeLoopDriver = nil
        pendingRestartStepID = nil
        activeEngine?.terminate()
        executionState = .idle
    }

    /// Immediate-kill variant for app quit. Bypasses the SIGTERM grace period
    /// so no orphan subprocesses remain after the dispatch queues drain.
    func forceStop() {
        guard executionState != .idle else { return }
        promptDispatcher.cancelWatcher()
        activeLoopDriver?.forceStop()
        activeLoopDriver = nil
        pendingRestartStepID = nil
        activeEngine?.terminate()
        executionState = .idle
    }

    /// Toggles a step's completion status for manual marking in the block editor.
    /// Only allowed when the engine is not actively executing.
    func toggleStepCompletion(stepID: String) {
        guard executionState != .executing else { return }
        if let index = completedStepIDs.firstIndex(of: stepID) {
            completedStepIDs.remove(at: index)
        } else {
            completedStepIDs.append(stepID)
        }
    }

    /// Clears completedStepIDs for all steps after the given position.
    func clearCompletionsFrom(phaseIndex: Int, stepIndex: Int) {
        var idsToRemove = Set<String>()
        for pi in phaseIndex..<workflow.phases.count {
            let startSI = (pi == phaseIndex) ? stepIndex + 1 : 0
            for si in startSI..<workflow.phases[pi].steps.count {
                idsToRemove.insert(workflow.phases[pi].steps[si].id)
            }
        }
        completedStepIDs.removeAll { idsToRemove.contains($0) }
    }

    /// Positions the engine at a specific step, clears completions from that step onward,
    /// and starts (or restarts) execution. Safe to call while executing — cancels any
    /// in-flight watcher and stops any active loop driver without terminating the Agent
    /// Session, so Claude retains its conversation history across retries.
    func runFromStep(phaseIndex: Int, stepIndex: Int) {
        promptDispatcher.cancelWatcher()
        activeLoopDriver?.stop()
        activeLoopDriver = nil
        pendingRestartStepID = nil
        var idsToRemove = Set<String>()
        for pi in phaseIndex..<workflow.phases.count {
            let startSI = (pi == phaseIndex) ? stepIndex : 0
            for si in startSI..<workflow.phases[pi].steps.count {
                idsToRemove.insert(workflow.phases[pi].steps[si].id)
            }
        }
        completedStepIDs.removeAll { idsToRemove.contains($0) }
        currentPhaseIndex = phaseIndex
        currentStepIndex = stepIndex
        executionState = .executing
        advanceLoop()
    }

    // MARK: - Core Advance Loop
    // NOTE: Loop and iterate_tasks are now step-level blocks with nested children.
    // This engine currently only processes flat phase steps linearly.
    // Executing nested children inside loop/iterate_tasks blocks is a required
    // follow-up before those block types can function.

    private func advanceLoop() {
        while executionState == .executing {
            guard currentPhaseIndex < workflow.phases.count else {
                executionState = .completed
                return
            }

            let phase = workflow.phases[currentPhaseIndex]

            // Find next incomplete step within the current phase
            var nextStepIndex: Int?
            for si in currentStepIndex..<phase.steps.count {
                if !completedStepIDs.contains(phase.steps[si].id) {
                    nextStepIndex = si
                    break
                }
            }

            guard let si = nextStepIndex else {
                // All steps in current phase are complete — advance to next phase
                currentPhaseIndex += 1
                currentStepIndex = 0
                continue
            }

            currentStepIndex = si
            let step = phase.steps[si]

            record(.stepStarted, "\(phase.name) · \(step.displayName)")

            switch step.type {
            case .prompt:
                // Resolve agent: step-level → SettingsStore phase preset → workflow inheritance chain.
                let agent = resolvedAgentForPromptStep(step, in: phase)
                let engine = engineResolver(agent)
                activeEngine = engine
                if let promptText = step.prompt {
                    engine.onStepComplete = { [weak self] in
                        DispatchQueue.main.async { self?.handleStepCompletion() }
                    }
                    engine.onProcessExit = { [weak self] in
                        DispatchQueue.main.async { self?.handleProcessCrash() }
                    }
                    var text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let seed = pendingSeed {
                        text = "\(seed)\n\(text)"
                        pendingSeed = nil
                    }
                    let progressPath = (signalFilePath as NSString).deletingLastPathComponent
                    // swiftlint:disable:next force_try
                    let wrapped = try! PromptSignalFooterWrapper.wrap(
                        promptBody: text,
                        progressPath: progressPath,
                        sessionId: session.id.uuidString
                    )
                    promptDispatcher.dispatch(wrapped, to: engine, signalFilePath: signalFilePath)
                    let agentLabel = agent ?? "default"
                    record(.promptSent, "Injected prompt to \(agentLabel)")
                } else {
                    // No prompt to inject — mark step complete immediately
                    completedStepIDs.append(step.id)
                    record(.skipped, "\(step.displayName) (no prompt)")
                    continue
                }
                return

            case .restartCLI:
                let engine = engineResolver(resolvedAgentForPromptStep(step, in: phase))
                activeEngine = engine
                let stepID = step.id
                let displayName = step.displayName
                let workingDir = session.workingDirectory
                let tool = resolvedAgentForPromptStep(step, in: phase) ?? ""
                let action = restartCLIAction ?? { eng, wd, t in
                    await TerminalRestartCoordinator().restart(engine: eng, workingDirectory: wd, tool: t)
                }
                Task { [weak self] in
                    let result = await action(engine, workingDir, tool)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.executionState == .executing else { return }
                        switch result {
                        case .success:
                            self.completedStepIDs.append(stepID)
                            self.record(.stepCompleted, displayName)
                            self.advanceLoop()
                        case .failure(let error):
                            self.pendingRestartStepID = stepID
                            self.executionState = .paused
                            self.record(.paused, "Restart CLI failed: \(error)")
                        }
                    }
                }
                return

            case .pause:
                executionState = .paused
                record(.paused, "\(step.displayName)")
                return // halt: continueExecution() will re-enter advanceLoop

            case .break_:
                // Break steps are auto-completed in linear execution.
                // Break-out-of-loop behavior requires the loop block engine update.
                completedStepIDs.append(step.id)

            case .comment:
                // Comments are skipped by the execution engine
                completedStepIDs.append(step.id)

            case .iterateTasks:
                let progressDir = (signalFilePath as NSString).deletingLastPathComponent
                let workingDirURL = URL(fileURLWithPath: session.workingDirectory)
                let progressDirURL = URL(fileURLWithPath: progressDir)
                let makeRunner: () -> any ProcessRunner
                if let override = processRunnerOverride {
                    makeRunner = { override }
                } else {
                    makeRunner = { [weak self] in
                        let preset = self?.settingsStore?.settings.buildCLI ?? .claude
                        return (try? ProcessRunnerFactory.make(preset: preset)) ?? ClaudeProcessRunner()
                    }
                }
                let driver = HeadlessRalphDriver(
                    workingDirectory: workingDirURL,
                    progressDirectory: progressDirURL,
                    maxIterations: step.maxIterations,
                    makeProcessRunner: makeRunner,
                    readPasses: { WorkflowEngine.readPasses(progressDir: progressDir) },
                    readCurrentTask: { WorkflowEngine.readCurrentTask(progressDir: progressDir) }
                )
                activeLoopDriver = driver
                let stepID = step.id
                driver.onStateChange = { [weak self] driverState in
                    DispatchQueue.main.async {
                        switch driverState {
                        case .completed:
                            self?.handleLoopDriverCompletion(stepID: stepID)
                        case .stalled:
                            self?.handleLoopDriverStalled()
                        default:
                            break
                        }
                    }
                }
                driver.onSubprocessExit = { [weak self] iter, exitCode in
                    DispatchQueue.main.async {
                        self?.record(
                            exitCode == 0 ? .stepCompleted : .crashed,
                            "iter \(iter) claude exited with code \(exitCode)"
                        )
                    }
                }
                driver.onIterationComplete = { [weak self] count, passes in
                    Task { @MainActor [weak self] in
                        self?.loopIterationCount = count
                        self?.sessionRunStatus?.applyIteration(count: count, passes: passes)
                    }
                }
                driver.onIterationStart = { [weak self] iteration, taskID, taskDescription in
                    Task { @MainActor [weak self] in
                        self?.sessionRunStatus?.beginIteration(
                            number: iteration, taskID: taskID, taskDescription: taskDescription)
                    }
                }
                driver.onEvent = { [weak self] events in
                    Task { @MainActor [weak self] in
                        let status = self?.sessionRunStatus
                        for event in events { status?.appendEvent(event) }
                    }
                }
                driver.start()
                return

            case .loop:
                // TODO: Execute nested children. For now, mark container as completed.
                completedStepIDs.append(step.id)
            }
        }
    }

    // MARK: - Task Iteration Support

    /// Reads `passes` values from tasks.json in `progressDir`. Returns an
    /// empty array when the file is missing or malformed — LoopDriver treats
    /// an empty array as "no tasks pass" and continues iterating.
    static func readPasses(progressDir: String) -> [Bool] {
        struct TaskEntry: Decodable { var passes: Bool }
        let tasksPath = (progressDir as NSString).appendingPathComponent("tasks.json")
        guard let data = FileManager.default.contents(atPath: tasksPath),
              let tasks = try? JSONDecoder().decode([TaskEntry].self, from: data) else {
            return []
        }
        return tasks.map(\.passes)
    }

    /// Returns the first unpassed Task's `id`, `description`, and resolved `Effort` from
    /// tasks.json in `progressDir`. Used to populate Iteration Cards.
    static func readCurrentTask(progressDir: String) -> (id: Int, description: String, effort: Effort)? {
        struct TaskEntry: Decodable { var id: Int; var description: String; var passes: Bool; var effort: String? }
        let tasksPath = (progressDir as NSString).appendingPathComponent("tasks.json")
        guard let data = FileManager.default.contents(atPath: tasksPath),
              let tasks = try? JSONDecoder().decode([TaskEntry].self, from: data) else {
            return nil
        }
        guard let task = tasks.first(where: { !$0.passes }) else { return nil }
        return (id: task.id, description: task.description, effort: Effort(raw: task.effort))
    }


    // MARK: - LoopDriver Callbacks

    private func handleLoopDriverCompletion(stepID: String) {
        guard executionState == .executing else { return }
        activeLoopDriver = nil
        activeEngine?.onProcessExit = nil
        if !completedStepIDs.contains(stepID) {
            completedStepIDs.append(stepID)
        }
        record(.stepCompleted, stepID)
        advanceLoop()
    }

    private func handleLoopDriverStalled() {
        guard executionState == .executing else { return }
        activeLoopDriver = nil
        activeEngine?.onProcessExit = nil
        executionState = .stalled
        record(.paused, "Iterate-tasks stalled after \(HeadlessRalphDriver.stallLimit) no-progress iterations")
    }

    // MARK: - Agent Resolution

    /// Resolves the AgentEngine tool identifier for a prompt step.
    ///
    /// Priority: step.agent (explicit) → SettingsStore phase-specific preset
    /// → workflow inheritance chain (phase.defaultAgent → workflow.defaultAgent).
    private func resolvedAgentForPromptStep(_ step: WorkflowStep, in phase: Phase) -> String? {
        if let a = step.agent, !a.isEmpty { return a }
        if let store = settingsStore {
            switch phase.name.lowercased() {
            case "plan":
                return ProcessRunnerFactory.toolIdentifier(for: store.settings.planCLI)
            case "verify":
                return ProcessRunnerFactory.toolIdentifier(for: store.settings.verifyCLI)
            default:
                break
            }
        }
        return workflow.resolvedAgent(for: step, in: phase)
    }

    // MARK: - Navigation

    private func findNextIncompleteStep(fromPhase phaseIndex: Int, stepIndex: Int) -> (Int, Int)? {
        var startStep = stepIndex
        for pi in phaseIndex..<workflow.phases.count {
            let phase = workflow.phases[pi]
            for si in startStep..<phase.steps.count {
                if !completedStepIDs.contains(phase.steps[si].id) {
                    return (pi, si)
                }
            }
            startStep = 0
        }
        return nil
    }

    // MARK: - Signal File Watching

    private func handleStepCompletion() {
        promptDispatcher.cancelWatcher()
        activeEngine?.onProcessExit = nil  // step succeeded — don't treat later exit as crash
        guard executionState == .executing else { return }
        let step = workflow.phases[currentPhaseIndex].steps[currentStepIndex]
        if !completedStepIDs.contains(step.id) {
            completedStepIDs.append(step.id)
        }
        record(.stepCompleted, step.displayName)
        advanceLoop()
    }
}
