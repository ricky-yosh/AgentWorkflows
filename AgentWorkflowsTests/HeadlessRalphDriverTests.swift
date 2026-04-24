import Foundation
import Testing
@testable import AgentWorkflows

@Suite("HeadlessRalphDriver")
struct HeadlessRalphDriverTests {

    // MARK: - Fakes

    final class FakeProcessRunner: ProcessRunner {
        struct Call {
            let effort: Effort
            let onEvent: ([IterationEvent]) -> Void
            let onRawLine: (String) -> Void
            let onExit: (Int32) -> Void
            let handle: FakeProcessHandle
        }

        private(set) var calls: [Call] = []

        @discardableResult
        func run(
            workingDirectory: URL,
            progressDirectory: URL,
            effort: Effort,
            onEvent: @escaping ([IterationEvent]) -> Void,
            onRawLine: @escaping (String) -> Void,
            onExit: @escaping (Int32) -> Void
        ) -> any ProcessHandle {
            let handle = FakeProcessHandle()
            calls.append(Call(effort: effort, onEvent: onEvent, onRawLine: onRawLine, onExit: onExit, handle: handle))
            return handle
        }

        /// Simulate the most recent subprocess exiting.
        func fireExit(exitCode: Int32 = 0) {
            calls.last?.onExit(exitCode)
        }

        var spawnCount: Int { calls.count }
        var lastHandle: FakeProcessHandle? { calls.last?.handle }
    }

    final class FakeProcessHandle: ProcessHandle {
        private(set) var terminateCalled = false
        private(set) var killImmediatelyCalled = false
        func terminate() { terminateCalled = true }
        func killImmediately() { killImmediatelyCalled = true }
    }

    // MARK: - Helpers

    private func makeDriver(
        maxIterations: Int? = 25,
        processRunner: FakeProcessRunner,
        passes: @escaping () -> [Bool]
    ) -> HeadlessRalphDriver {
        HeadlessRalphDriver(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            progressDirectory: URL(fileURLWithPath: "/tmp/.aw-cache/ralph"),
            maxIterations: maxIterations,
            makeProcessRunner: { processRunner },
            readPasses: passes
        )
    }

    // MARK: - Start

    @Test func startSpawnsSubprocess() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [true] })
        driver.start()

        #expect(runner.spawnCount == 1)
        #expect(driver.state == .running)
    }

    @Test func startIsIdempotent() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [true] })
        driver.start()
        driver.start()

        #expect(runner.spawnCount == 1)
    }

    // MARK: - Convergence

    @Test func allPassesConvergesAfterTwoIterations() {
        var call = 0
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: {
            call += 1
            return call == 1 ? [false, true] : [true, true]
        })
        driver.start()

        runner.fireExit()   // Iteration 1 — not converged
        #expect(driver.state == .running)
        #expect(runner.spawnCount == 2)

        runner.fireExit()   // Iteration 2 — all pass
        #expect(driver.state == .completed)
        #expect(runner.spawnCount == 2, "no further spawns after convergence")
        #expect(driver.iterationCount == 2)
    }

    // MARK: - Stall Detection

    @Test func stallDetectionTerminatesAfterThreeNoProgressIterations() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [false, false, false] })
        driver.start()

        runner.fireExit()   // iteration 1 — stallCount = 1
        #expect(driver.state == .running)
        runner.fireExit()   // iteration 2 — stallCount = 2
        #expect(driver.state == .running)
        runner.fireExit()   // iteration 3 — stallCount = 3 → stalled
        #expect(driver.state == .stalled)
        #expect(driver.iterationCount == 3)
    }

    @Test func progressResetsStallCount() {
        var call = 0
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: {
            call += 1
            switch call {
            case 1: return [false, false]
            case 2: return [false, false]   // stallCount → 2
            case 3: return [true, false]    // progress — resets to 1
            default: return [true, false]   // stallCount → 2
            }
        })
        driver.start()

        runner.fireExit()
        runner.fireExit()
        runner.fireExit()
        runner.fireExit()
        #expect(driver.state == .running, "progress on iter 3 clears the stall streak")
    }

    // MARK: - Max Iterations

    @Test func maxIterationsWithoutConvergenceTerminatesAsStalled() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(
            maxIterations: 2,
            processRunner: runner,
            passes: { [false, true] }
        )
        driver.start()

        runner.fireExit()
        #expect(driver.state == .running)
        runner.fireExit()
        #expect(driver.state == .stalled)
        #expect(driver.iterationCount == 2)
        #expect(driver.terminalReason == .maxIterations, "maxIterations reason distinguishes from stall")
    }

    @Test func maxIterationsWithConvergenceCompletes() {
        var call = 0
        let runner = FakeProcessRunner()
        let driver = makeDriver(
            maxIterations: 2,
            processRunner: runner,
            passes: {
                call += 1
                return call >= 2 ? [true, true] : [false, true]
            }
        )
        driver.start()

        runner.fireExit()   // iteration 1 — not converged
        #expect(driver.state == .running)
        runner.fireExit()   // iteration 2 — convergence wins over cap
        #expect(driver.state == .completed)
    }

    // MARK: - Stop

    @Test func stopMidIterationTerminatesHandle() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [false] })
        driver.start()

        let handle = runner.lastHandle
        driver.stop()

        #expect(driver.state == .stopped)
        #expect(handle?.terminateCalled == true)
    }

    @Test func exitAfterStopIsIgnored() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [false] })
        driver.start()
        driver.stop()

        runner.fireExit()
        #expect(driver.state == .stopped, "exit after stop must not change state")
        #expect(runner.spawnCount == 1, "no new spawn after stop")
    }

    // MARK: - Terminal Reasons

    @Test func terminalReasonIsCompletedOnConvergence() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [true, true] })
        driver.start()
        runner.fireExit()
        #expect(driver.terminalReason == .completed)
    }

    @Test func terminalReasonIsStalledAfterThreeNoProgressIterations() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [false] })
        driver.start()
        runner.fireExit()
        runner.fireExit()
        runner.fireExit()
        #expect(driver.terminalReason == .stalled)
    }

    @Test func terminalReasonIsMaxIterationsWhenBudgetExhausted() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(maxIterations: 2, processRunner: runner, passes: { [false] })
        driver.start()
        runner.fireExit()
        runner.fireExit()
        #expect(driver.terminalReason == .maxIterations)
    }

    @Test func terminalReasonIsStoppedOnStop() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [false] })
        driver.start()
        driver.stop()
        #expect(driver.terminalReason == .stopped)
    }

    // MARK: - Pause / Resume

    @Test func pauseLetsCurentIterationFinishWithoutSpawningNext() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [false] })
        driver.start()
        #expect(runner.spawnCount == 1)

        driver.pause()
        #expect(driver.state == .paused)

        runner.fireExit()
        #expect(driver.state == .paused, "exit while paused should not spawn next")
        #expect(runner.spawnCount == 1, "no new spawn while paused")
    }

    @Test func resumeAfterPauseSpawnsNextIteration() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [false] })
        driver.start()

        driver.pause()
        runner.fireExit()
        #expect(driver.state == .paused)

        driver.resume()
        #expect(driver.state == .running)
        #expect(runner.spawnCount == 2, "resume spawns next iteration")
    }

    // MARK: - Iteration Start Callback

    @Test func onIterationStartFiresWithCurrentTask() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [false, false] })
        var starts: [(iteration: Int, taskID: Int?, taskDescription: String?)] = []
        driver.onIterationStart = { iteration, taskID, desc in
            starts.append((iteration: iteration, taskID: taskID, taskDescription: desc))
        }

        driver.start()
        #expect(starts.count == 1)
        #expect(starts[0].iteration == 1)

        runner.fireExit()   // second iteration spawned
        #expect(starts.count == 2)
        #expect(starts[1].iteration == 2)
    }

    @Test func onIterationStartFiresWithTaskFromReadCurrentTask() {
        let runner = FakeProcessRunner()
        let driver = HeadlessRalphDriver(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            progressDirectory: URL(fileURLWithPath: "/tmp/.aw-cache/ralph"),
            maxIterations: 25,
            makeProcessRunner: { runner },
            readPasses: { [false] },
            readCurrentTask: { (id: 3, description: "Do the thing", effort: .medium) }
        )
        var receivedTaskID: Int?
        var receivedDesc: String?
        driver.onIterationStart = { _, taskID, desc in
            receivedTaskID = taskID
            receivedDesc = desc
        }

        driver.start()
        #expect(receivedTaskID == 3)
        #expect(receivedDesc == "Do the thing")
    }

    // MARK: - Event Capture

    @Test func onEventCallbackForwardsEventsFromProcessRunner() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [true] })
        var captured: [IterationEvent] = []
        driver.onEvent = { events in captured.append(contentsOf: events) }

        driver.start()
        runner.calls.last?.onEvent([
            .assistantText("hello"),
            .toolUse(name: "Bash", inputSummary: "ls"),
        ])
        runner.fireExit()

        #expect(captured.count == 2)
        #expect(captured[0] == .assistantText("hello"))
        #expect(captured[1] == .toolUse(name: "Bash", inputSummary: "ls"))
    }

    @Test func onEventReflectsLatestToolUseForLiveToolCallLine() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [true] })
        var lastToolUse: (name: String, inputSummary: String)?
        driver.onEvent = { events in
            for event in events {
                if case .toolUse(let name, let summary) = event {
                    lastToolUse = (name: name, inputSummary: summary)
                }
            }
        }

        driver.start()
        runner.calls.last?.onEvent([.toolUse(name: "Read", inputSummary: "file.swift")])
        runner.calls.last?.onEvent([.toolUse(name: "Edit", inputSummary: "file.swift")])

        #expect(lastToolUse?.name == "Edit")
        #expect(lastToolUse?.inputSummary == "file.swift")
    }

    // MARK: - Callbacks

    @Test func stateChangeCallbackFires() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [true] })
        var observed: [HeadlessRalphDriver.State] = []
        driver.onStateChange = { observed.append($0) }

        driver.start()
        runner.fireExit()

        #expect(observed.first == .running)
        #expect(observed.last == .completed)
    }

    @Test func iterationCompleteCallbackFires() {
        let runner = FakeProcessRunner()
        let driver = makeDriver(processRunner: runner, passes: { [true, false] })
        var callbackCount = 0
        var lastPasses: [Bool] = []
        driver.onIterationComplete = { _, passes in
            callbackCount += 1
            lastPasses = passes
        }

        driver.start()
        runner.fireExit()

        #expect(callbackCount == 1)
        #expect(lastPasses == [true, false])
    }

    // MARK: - Effort Forwarding Integration

    @Test func effortPerTaskIsForwardedToProcessRunner() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tasksURL = tempDir.appendingPathComponent("tasks.json")

        func writeTasks(_ json: String) throws {
            try json.data(using: .utf8)!.write(to: tasksURL)
        }

        try writeTasks("""
        [
          {"id": 1, "description": "Low task",     "passes": false, "effort": "low"},
          {"id": 2, "description": "Clamp task",   "passes": false, "effort": "xhigh"},
          {"id": 3, "description": "Default task", "passes": false}
        ]
        """)

        struct Entry: Decodable { var passes: Bool }

        let runner = FakeProcessRunner()
        let driver = HeadlessRalphDriver(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            progressDirectory: tempDir,
            maxIterations: nil,
            makeProcessRunner: { runner },
            readPasses: {
                guard let data = FileManager.default.contents(atPath: tasksURL.path),
                      let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
                return entries.map(\.passes)
            },
            readCurrentTask: { WorkflowEngine.readCurrentTask(progressDir: tempDir.path) }
        )

        // Iteration 1 – task 1 (effort "low" → .low)
        driver.start()
        #expect(runner.spawnCount == 1)
        try writeTasks("""
        [
          {"id": 1, "description": "Low task",     "passes": true,  "effort": "low"},
          {"id": 2, "description": "Clamp task",   "passes": false, "effort": "xhigh"},
          {"id": 3, "description": "Default task", "passes": false}
        ]
        """)
        runner.fireExit()

        // Iteration 2 – task 2 (effort "xhigh" → .high clamp)
        #expect(runner.spawnCount == 2)
        try writeTasks("""
        [
          {"id": 1, "description": "Low task",     "passes": true,  "effort": "low"},
          {"id": 2, "description": "Clamp task",   "passes": true,  "effort": "xhigh"},
          {"id": 3, "description": "Default task", "passes": false}
        ]
        """)
        runner.fireExit()

        // Iteration 3 – task 3 (effort field absent → .medium default)
        #expect(runner.spawnCount == 3)
        try writeTasks("""
        [
          {"id": 1, "description": "Low task",     "passes": true, "effort": "low"},
          {"id": 2, "description": "Clamp task",   "passes": true, "effort": "xhigh"},
          {"id": 3, "description": "Default task", "passes": true}
        ]
        """)
        runner.fireExit()

        #expect(driver.state == .completed)
        let efforts = runner.calls.map(\.effort)
        #expect(efforts == [.low, .high, .medium])
    }
}
