import Testing
@testable import AgentWorkflows

@Suite("IterateTasksTerminator")
struct IterateTasksTerminatorTests {

    typealias Terminator = IterateTasksTerminator
    typealias Task = IterateTasksTerminator.Task
    typealias Snapshot = IterateTasksTerminator.Snapshot

    // MARK: - Snapshot builder

    private func snapshot(
        tasks: [Task],
        iterationCount: Int = 1,
        maxIterations: Int? = nil,
        stallCount: Int = 1,
        stallLimit: Int = 3,
        stopped: Bool = false
    ) -> Snapshot {
        Snapshot(
            tasks: tasks,
            iterationCount: iterationCount,
            maxIterations: maxIterations,
            stallCount: stallCount,
            stallLimit: stallLimit,
            stopped: stopped
        )
    }

    // MARK: - Table-driven: all four termination conditions

    @Test(
        "termination reasons",
        arguments: [
            (
                "convergence — all tasks pass",
                Snapshot(tasks: [Task(passes: true), Task(passes: true)],
                         iterationCount: 1, maxIterations: nil,
                         stallCount: 1, stallLimit: 3, stopped: false),
                IterateTasksTerminator.Decision.terminate(.convergence)
            ),
            (
                "stall — consecutive no-progress iterations",
                Snapshot(tasks: [Task(passes: false)],
                         iterationCount: 5, maxIterations: nil,
                         stallCount: 3, stallLimit: 3, stopped: false),
                IterateTasksTerminator.Decision.terminate(.stall)
            ),
            (
                "maxIterations — cap reached without convergence",
                Snapshot(tasks: [Task(passes: false)],
                         iterationCount: 25, maxIterations: 25,
                         stallCount: 1, stallLimit: 3, stopped: false),
                IterateTasksTerminator.Decision.terminate(.maxIterations)
            ),
            (
                "stopped — external stop requested",
                Snapshot(tasks: [Task(passes: false)],
                         iterationCount: 3, maxIterations: nil,
                         stallCount: 1, stallLimit: 3, stopped: true),
                IterateTasksTerminator.Decision.terminate(.stopped)
            ),
        ] as [(String, Snapshot, IterateTasksTerminator.Decision)]
    )
    func terminationConditions(name: String, snap: Snapshot, expected: IterateTasksTerminator.Decision) {
        #expect(Terminator.decide(snapshot: snap) == expected)
    }

    @Test func continueWhenNoConditionMet() {
        let snap = snapshot(tasks: [Task(passes: false)], iterationCount: 5, maxIterations: 25,
                            stallCount: 2, stallLimit: 3)
        #expect(Terminator.decide(snapshot: snap) == .continue)
    }

    // MARK: - Convergence

    @Test func allTasksPassingTerminates() {
        let snap = snapshot(tasks: [Task(passes: true), Task(passes: true)])
        #expect(Terminator.decide(snapshot: snap) == .terminate(.convergence))
    }

    @Test func emptyTasksTerminates() {
        let snap = snapshot(tasks: [], iterationCount: 0)
        #expect(Terminator.decide(snapshot: snap) == .terminate(.convergence))
    }

    @Test func incompleteTasksWithoutCapContinues() {
        let snap = snapshot(tasks: [Task(passes: true), Task(passes: false)], iterationCount: 999)
        #expect(Terminator.decide(snapshot: snap) == .continue)
    }

    // MARK: - Max Iterations

    @Test func capReachedTerminatesEvenWithIncompleteTasks() {
        let snap = snapshot(tasks: [Task(passes: false), Task(passes: false)],
                            iterationCount: 25, maxIterations: 25)
        #expect(Terminator.decide(snapshot: snap) == .terminate(.maxIterations))
    }

    @Test func capExceededTerminates() {
        let snap = snapshot(tasks: [Task(passes: false)], iterationCount: 26, maxIterations: 25)
        #expect(Terminator.decide(snapshot: snap) == .terminate(.maxIterations))
    }

    @Test func underCapContinues() {
        let snap = snapshot(tasks: [Task(passes: false)], iterationCount: 5, maxIterations: 25)
        #expect(Terminator.decide(snapshot: snap) == .continue)
    }

    // MARK: - Stall

    @Test func stallAtLimitTerminates() {
        let snap = snapshot(tasks: [Task(passes: false)], stallCount: 3, stallLimit: 3)
        #expect(Terminator.decide(snapshot: snap) == .terminate(.stall))
    }

    @Test func stallBelowLimitContinues() {
        let snap = snapshot(tasks: [Task(passes: false)], stallCount: 2, stallLimit: 3)
        #expect(Terminator.decide(snapshot: snap) == .continue)
    }

    // MARK: - External stop

    @Test func stoppedTerminatesImmediately() {
        let snap = snapshot(tasks: [Task(passes: false)], stopped: true)
        #expect(Terminator.decide(snapshot: snap) == .terminate(.stopped))
    }

    @Test func stoppedTakesPriorityOverConvergence() {
        let snap = snapshot(tasks: [Task(passes: true)], stopped: true)
        #expect(Terminator.decide(snapshot: snap) == .terminate(.stopped))
    }

    // MARK: - Priority ordering

    @Test func convergenceTakesPriorityOverMaxIterations() {
        let snap = snapshot(tasks: [Task(passes: true)], iterationCount: 25, maxIterations: 25)
        #expect(Terminator.decide(snapshot: snap) == .terminate(.convergence))
    }

    @Test func convergenceTakesPriorityOverStall() {
        let snap = snapshot(tasks: [Task(passes: true)], stallCount: 3, stallLimit: 3)
        #expect(Terminator.decide(snapshot: snap) == .terminate(.convergence))
    }

    // MARK: - loopDecide (loop:true phases)

    @Test func loopBreakFiredTerminates() {
        let decision = Terminator.loopDecide(breakFired: true, iterationCount: 3, maxIterations: nil)
        #expect(decision == .terminate(.convergence))
    }

    @Test func loopUnboundedWithoutBreakContinues() {
        let decision = Terminator.loopDecide(breakFired: false, iterationCount: 9999, maxIterations: nil)
        #expect(decision == .continue)
    }

    @Test func loopCapReachedTerminates() {
        let decision = Terminator.loopDecide(breakFired: false, iterationCount: 10, maxIterations: 10)
        #expect(decision == .terminate(.maxIterations))
    }

    @Test func loopUnderCapContinues() {
        let decision = Terminator.loopDecide(breakFired: false, iterationCount: 4, maxIterations: 10)
        #expect(decision == .continue)
    }

    @Test func loopBreakBeatsCap() {
        let decision = Terminator.loopDecide(breakFired: true, iterationCount: 100, maxIterations: 10)
        #expect(decision == .terminate(.convergence))
    }
}
