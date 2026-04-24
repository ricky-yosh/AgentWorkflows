import Foundation

/// Four precise reasons a `HeadlessRalphDriver` stopped running.
/// Distinguishes `.stalled` (no progress) from `.maxIterations` (budget
/// exhausted) so the UI and WorkflowEngine can treat them differently.
enum DriverTerminalState: Equatable {
    case completed
    case stalled
    case maxIterations
    case stopped
}

extension DriverTerminalState {
    /// Maps each terminal reason to the user-visible `SessionState`.
    var sessionState: SessionState {
        switch self {
        case .completed:               return .completed
        case .stalled, .maxIterations: return .stalled
        case .stopped:                 return .idle
        }
    }
}

/// Drives Iterations inside an Iterate-Tasks Step by spawning a fresh
/// `claude -p` subprocess per Iteration via a `ProcessRunner`, parsing its
/// Stream-JSON Event output, and reading `tasks.json` on process exit to
/// compute Passes. Terminates via `IterateTasksTerminator`; detects Stall.
final class HeadlessRalphDriver {

    // MARK: - Types

    enum State: Equatable {
        case idle
        case running
        case paused
        case completed
        case stalled
        case stopped
    }

    // MARK: - Configuration

    static let stallLimit: Int = 3

    // MARK: - Inputs

    let workingDirectory: URL
    let progressDirectory: URL
    let maxIterations: Int?
    private let makeProcessRunner: () -> any ProcessRunner
    private let readPasses: () -> [Bool]
    private let readCurrentTask: () -> (id: Int, description: String, effort: Effort)?
    private let logWriter: IterationLogWriter

    // MARK: - Outputs (callbacks — UI glue binds these)

    var onStateChange: ((State) -> Void)?
    var onIterationComplete: ((_ iterationCount: Int, _ passes: [Bool]) -> Void)?
    /// Fires once per claude subprocess exit with the raw exit code. Lets the
    /// WorkflowEngine surface the code as an ExecutionEvent so users can tell
    /// a silent instant-stall apart from a real no-progress stall.
    var onSubprocessExit: ((_ iterationCount: Int, _ exitCode: Int32) -> Void)?
    /// Called at the start of each Iteration with the iteration number and the
    /// first unpassed Task's id + description (nil if tasks.json is unreadable).
    var onIterationStart: ((_ iteration: Int, _ taskID: Int?, _ taskDescription: String?) -> Void)?
    /// Called with each batch of IterationEvents decoded from one stdout line.
    var onEvent: (([IterationEvent]) -> Void)?

    // MARK: - State

    private(set) var state: State = .idle {
        didSet { if oldValue != state { onStateChange?(state) } }
    }

    private(set) var iterationCount: Int = 0
    private(set) var stallCount: Int = 0
    private(set) var terminalReason: DriverTerminalState?
    private var lastPasses: [Bool]?
    private var currentHandle: (any ProcessHandle)?

    // MARK: - Init

    init(
        workingDirectory: URL,
        progressDirectory: URL,
        maxIterations: Int?,
        makeProcessRunner: @escaping () -> any ProcessRunner,
        readPasses: @escaping () -> [Bool],
        readCurrentTask: @escaping () -> (id: Int, description: String, effort: Effort)? = { nil }
    ) {
        self.workingDirectory = workingDirectory
        self.progressDirectory = progressDirectory
        self.maxIterations = maxIterations
        self.makeProcessRunner = makeProcessRunner
        self.readPasses = readPasses
        self.readCurrentTask = readCurrentTask
        self.logWriter = IterationLogWriter(progressDirectory: progressDirectory)
    }

    // MARK: - Public API

    func start() {
        guard state == .idle else { return }
        state = .running
        spawnNext()
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
    }

    /// Resume after pause. Spawns the next Iteration if no subprocess is
    /// currently in flight (i.e. pause happened between Iterations).
    func resume() {
        guard state == .paused else { return }
        state = .running
        if currentHandle == nil { spawnNext() }
    }

    func stop() {
        let wasActive = state == .running || state == .paused
        guard wasActive else { return }
        terminalReason = .stopped
        state = .stopped
        currentHandle?.terminate()
        currentHandle = nil
    }

    /// Immediate-kill variant for app quit. Sends SIGKILL synchronously so the
    /// subprocess is guaranteed to die before the dispatch queues drain.
    func forceStop() {
        let wasActive = state == .running || state == .paused
        guard wasActive else { return }
        terminalReason = .stopped
        state = .stopped
        currentHandle?.killImmediately()
        currentHandle = nil
    }

    /// Wires `onStateChange` and `onIterationComplete` to a `SessionRunStatus`
    /// so the Status Strip updates live. Replaces any previously assigned callbacks.
    @MainActor
    func bind(to status: SessionRunStatus) {
        status.maxIterations = maxIterations ?? status.maxIterations
        onStateChange = { [weak self, weak status] driverState in
            Task { @MainActor in
                status?.driverState = driverState
                status?.driverTerminalReason = self?.terminalReason
                switch driverState {
                case .running:
                    if status?.startedAt == nil { status?.beginRun() }
                case .completed, .stalled, .stopped, .idle:
                    status?.finishRun()
                case .paused:
                    break
                }
            }
        }
        onIterationComplete = { [weak status] count, passes in
            Task { @MainActor in
                status?.applyIteration(count: count, passes: passes)
            }
        }
    }

    // MARK: - Iteration

    private func spawnNext() {
        guard state == .running else { return }
        let iteration = iterationCount + 1
        try? logWriter.open(iteration: iteration)

        let task = readCurrentTask()
        onIterationStart?(iteration, task?.id, task?.description)

        let runner = makeProcessRunner()
        let handle = runner.run(
            workingDirectory: workingDirectory,
            progressDirectory: progressDirectory,
            effort: task?.effort ?? .medium,
            onEvent: { [weak self] events in self?.onEvent?(events) },
            onRawLine: { [weak self] line in self?.logWriter.append(line) },
            onExit: { [weak self] exitCode in self?.handleProcessExit(exitCode: exitCode) }
        )
        currentHandle = handle
    }

    private func handleProcessExit(exitCode: Int32) {
        logWriter.close()
        currentHandle = nil

        guard state == .running || state == .paused else { return }

        iterationCount += 1
        onSubprocessExit?(iterationCount, exitCode)
        let passes = readPasses()
        onIterationComplete?(iterationCount, passes)

        if let last = lastPasses, last == passes {
            stallCount += 1
        } else {
            stallCount = 1
        }
        lastPasses = passes

        let snapshot = IterateTasksTerminator.Snapshot(
            tasks: passes.map { IterateTasksTerminator.Task(passes: $0) },
            iterationCount: iterationCount,
            maxIterations: maxIterations,
            stallCount: stallCount,
            stallLimit: Self.stallLimit,
            stopped: state == .stopped
        )

        switch IterateTasksTerminator.decide(snapshot: snapshot) {
        case .terminate(.stall):
            terminalReason = .stalled
            state = .stalled
            return
        case .terminate(.stopped):
            terminalReason = .stopped
            state = .stopped
            return
        case .terminate(.maxIterations):
            terminalReason = .maxIterations
            state = .stalled
            return
        case .terminate:
            terminalReason = .completed
            state = .completed
            return
        case .continue:
            break
        }

        // If paused between Iterations, wait for resume().
        if state == .paused { return }

        spawnNext()
    }
}
