import Testing
import Foundation
@testable import AgentWorkflows

// MARK: - FakeAgentEngine

/// Test double for TerminalRestartCoordinator tests. Programmable to simulate
/// stop failure, start failure, and deferred ready signals.
final class FakeAgentEngine: AgentEngine {
    var engineState: EngineState = .running
    var onStepComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?
    var onProcessReady: (() -> Void)?

    var shouldKeepRunningAfterStop = false
    var shouldThrowOnStart = false
    private(set) var stopCalls = 0
    private(set) var startCalls: [(workingDirectory: String, tool: String)] = []

    func terminate() {
        stopCalls += 1
        if !shouldKeepRunningAfterStop {
            engineState = .idle
        }
    }

    func start(workingDirectory: String, tool: String) throws {
        if shouldThrowOnStart {
            throw CocoaError(.fileNoSuchFile)
        }
        startCalls.append((workingDirectory, tool))
        engineState = .running
    }

    func injectPrompt(_ text: String) {}

    func simulateReady() {
        onProcessReady?()
    }
}

// MARK: - TerminalRestartCoordinatorTests

@Suite("TerminalRestartCoordinator")
struct TerminalRestartCoordinatorTests {

    @Test func happyPathCallsStopThenStartAndReturnsSuccess() async throws {
        let engine = FakeAgentEngine()
        engine.engineState = .running
        let coordinator = TerminalRestartCoordinator(readyTimeout: .seconds(2))

        async let result = coordinator.restart(engine: engine, workingDirectory: "/tmp", tool: "claude")

        try await Task.sleep(for: .milliseconds(20))
        engine.simulateReady()

        let outcome = await result
        guard case .success = outcome else {
            Issue.record("Expected .success, got \(outcome)")
            return
        }
        #expect(engine.stopCalls == 1)
        #expect(engine.startCalls.count == 1)
        #expect(engine.startCalls[0].workingDirectory == "/tmp")
        #expect(engine.startCalls[0].tool == "claude")
    }

    @Test func stopPrecedesStart() async throws {
        let engine = FakeAgentEngine()
        engine.engineState = .running
        let coordinator = TerminalRestartCoordinator(readyTimeout: .seconds(2))

        async let result = coordinator.restart(engine: engine, workingDirectory: "/tmp", tool: "claude")

        try await Task.sleep(for: .milliseconds(20))
        #expect(engine.stopCalls == 1)
        #expect(engine.startCalls.count == 1)
        engine.simulateReady()

        _ = await result
    }

    @Test func stopFailureProducesDistinctError() async {
        let engine = FakeAgentEngine()
        engine.engineState = .running
        engine.shouldKeepRunningAfterStop = true
        let coordinator = TerminalRestartCoordinator(readyTimeout: .milliseconds(50))

        let result = await coordinator.restart(engine: engine, workingDirectory: "/tmp", tool: "claude")

        guard case .failure(let error) = result else {
            Issue.record("Expected .failure, got \(result)")
            return
        }
        #expect(error == .stopFailed)
        #expect(engine.startCalls.isEmpty)
    }

    @Test func startFailureProducesDistinctError() async {
        let engine = FakeAgentEngine()
        engine.engineState = .running
        engine.shouldThrowOnStart = true
        let coordinator = TerminalRestartCoordinator(readyTimeout: .milliseconds(50))

        let result = await coordinator.restart(engine: engine, workingDirectory: "/tmp", tool: "claude")

        guard case .failure(let error) = result else {
            Issue.record("Expected .failure, got \(result)")
            return
        }
        #expect(error == .startFailed)
    }

    @Test func readyTimeoutProducesDistinctError() async {
        let engine = FakeAgentEngine()
        engine.engineState = .running
        let coordinator = TerminalRestartCoordinator(readyTimeout: .milliseconds(50))

        let result = await coordinator.restart(engine: engine, workingDirectory: "/tmp", tool: "claude")

        guard case .failure(let error) = result else {
            Issue.record("Expected .failure, got \(result)")
            return
        }
        #expect(error == .readyTimeout)
        #expect(engine.onProcessReady == nil, "coordinator must clear callback after timeout")
    }

    @Test func skipsStopWhenEngineIsAlreadyIdle() async throws {
        let engine = FakeAgentEngine()
        engine.engineState = .idle
        let coordinator = TerminalRestartCoordinator(readyTimeout: .seconds(2))

        async let result = coordinator.restart(engine: engine, workingDirectory: "/tmp", tool: "claude")

        try await Task.sleep(for: .milliseconds(20))
        engine.simulateReady()

        let outcome = await result
        guard case .success = outcome else {
            Issue.record("Expected .success, got \(outcome)")
            return
        }
        #expect(engine.stopCalls == 0, "stop must be skipped for already-idle engine")
        #expect(engine.startCalls.count == 1)
    }

    @Test func simulatingReadyAfterTimeoutDoesNotCrash() async throws {
        let engine = FakeAgentEngine()
        engine.engineState = .running
        let coordinator = TerminalRestartCoordinator(readyTimeout: .milliseconds(50))

        let result = await coordinator.restart(engine: engine, workingDirectory: "/tmp", tool: "claude")
        guard case .failure = result else {
            Issue.record("Expected .failure, got \(result)")
            return
        }

        // Stale ready signal after coordinator has returned — must not crash
        engine.simulateReady()
    }
}
