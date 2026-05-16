import Foundation
import Observation

/// Per-iteration snapshot consumed by `IterationCardView`.
struct IterationRecord: Identifiable {
    let id: Int                     // iteration number (1-based)
    let taskID: Int?                // first unpassed Task's `id` field in tasks.json
    let taskDescription: String?    // that task's `description` field
    var sessionId: String?          // Anthropic session id from the sessionStarted event
    let startDate: Date
    var endDate: Date?              // set when the iteration's subprocess exits
    var events: [IterationEvent]
}

/// Live status for a Session's run — the data surface behind
/// `SessionHeaderStatus` and `SessionCardStatus`. Populated by the
/// `HeadlessRalphDriver` via its `onStateChange` / `onIterationComplete` callbacks.
@Observable
@MainActor
final class SessionRunStatus {
    var driverState: HeadlessRalphDriver.State = .idle

    /// Precise reason the driver stopped. Non-nil only after the driver reaches
    /// a terminal state; cleared when a new run begins. Use this to distinguish
    /// `.maxIterations` from `.stalled` when both surface as `SessionState.stalled`.
    var driverTerminalReason: DriverTerminalState?

    /// Completed Iteration count (N).
    var iterationCount: Int = 0

    /// Cap from Workflow.ralph (default 25).
    var maxIterations: Int

    /// Number of Tasks with `passes: true` (X).
    var tasksPassed: Int = 0

    /// Total Task count (Y).
    var tasksTotal: Int = 0

    /// Wall-clock start of the current run, nil when idle/completed/stalled.
    var startedAt: Date?

    /// Per-iteration records accumulated during the current run. Current
    /// iteration is `iterationRecords.last`. Cleared when a new run begins.
    var iterationRecords: [IterationRecord] = []

    /// Most-recent tool-use name + input summary from the current iteration.
    /// Updated in place as new `toolUse` events arrive; nil between iterations.
    var liveToolCall: (name: String, inputSummary: String)?

    /// Pi-reported provider/model label (for example, `mlx / Qwen3-Coder`).
    /// Set after the first `.modelIdentified` event in a run and displayed
    /// in the session sidebar status line.
    var sidebarModelLabel: String?

    init(maxIterations: Int = 25) {
        self.maxIterations = maxIterations
    }

    func beginRun(at date: Date = Date()) {
        iterationCount = 0
        tasksPassed = 0
        tasksTotal = 0
        startedAt = date
        driverTerminalReason = nil
        iterationRecords = []
        liveToolCall = nil
        sidebarModelLabel = nil
    }

    func beginIteration(number: Int, taskID: Int?, taskDescription: String?) {
        iterationRecords.append(IterationRecord(
            id: number,
            taskID: taskID,
            taskDescription: taskDescription,
            sessionId: nil,
            startDate: Date(),
            events: []
        ))
        liveToolCall = nil
    }

    func appendEvent(_ event: IterationEvent) {
        guard !iterationRecords.isEmpty else { return }
        let last = iterationRecords.count - 1
        iterationRecords[last].events.append(event)
        switch event {
        case .toolUse(let name, let inputSummary):
            liveToolCall = (name: name, inputSummary: inputSummary)
        case .sessionStarted(let sessionId):
            iterationRecords[last].sessionId = sessionId
        case .modelIdentified(let provider, let model):
            sidebarModelLabel = "\(provider) / \(model)"
        default:
            break
        }
    }

    func applyIteration(count: Int, passes: [Bool]) {
        iterationCount = count
        tasksPassed = passes.filter { $0 }.count
        tasksTotal = passes.count
        if !iterationRecords.isEmpty {
            iterationRecords[iterationRecords.count - 1].endDate = Date()
        }
    }

    func finishRun() {
        startedAt = nil
    }

    /// Live elapsed seconds since `startedAt`, or nil if not running.
    func elapsed(now: Date = Date()) -> TimeInterval? {
        guard let startedAt else { return nil }
        return max(0, now.timeIntervalSince(startedAt))
    }

    /// Formatted `HH:MM:SS` / `MM:SS` string for display.
    static func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
