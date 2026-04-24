import Foundation

/// Pure-function module that decides whether an iterate:tasks (or loop) phase
/// should terminate after an iteration. No engine globals; all inputs are
/// passed as a `Snapshot` so the same function governs Convergence, Stall,
/// Max Iterations, and external stop.
enum IterateTasksTerminator {

    /// Minimal Task view the terminator needs. Only `passes` is read.
    struct Task: Equatable {
        let passes: Bool
    }

    /// Full snapshot of iteration state passed to `decide`. Collecting all
    /// inputs here keeps the decision pure and table-testable.
    struct Snapshot {
        let tasks: [Task]
        let iterationCount: Int
        let maxIterations: Int?
        let stallCount: Int
        let stallLimit: Int
        let stopped: Bool
    }

    enum Reason: Equatable {
        case convergence    // every Task has passes == true
        case stall          // stallCount >= stallLimit
        case maxIterations  // iterationCount >= cap without convergence
        case stopped        // external stop requested
    }

    enum Decision: Equatable {
        case `continue`
        case terminate(Reason)

        var isTerminate: Bool {
            if case .terminate = self { return true }
            return false
        }
    }

    /// Decide whether to terminate based on the full iteration snapshot.
    ///
    /// Priority: stopped > convergence > stall > maxIterations > continue.
    static func decide(snapshot: Snapshot) -> Decision {
        if snapshot.stopped { return .terminate(.stopped) }
        if snapshot.tasks.allSatisfy(\.passes) { return .terminate(.convergence) }
        if snapshot.stallCount >= snapshot.stallLimit { return .terminate(.stall) }
        if let cap = snapshot.maxIterations, snapshot.iterationCount >= cap {
            return .terminate(.maxIterations)
        }
        return .continue
    }

    /// Decide whether to terminate a `loop:true` Phase. A break step firing is
    /// the primary termination signal; `maxIterations` is a safety cap.
    static func loopDecide(
        breakFired: Bool,
        iterationCount: Int,
        maxIterations: Int?
    ) -> Decision {
        let snapshot = Snapshot(
            tasks: [Task(passes: breakFired)],
            iterationCount: iterationCount,
            maxIterations: maxIterations,
            stallCount: 0,
            stallLimit: Int.max,
            stopped: false
        )
        return decide(snapshot: snapshot)
    }
}
