import Foundation

enum TerminalRestartError: Error, Equatable {
    case stopFailed
    case startFailed
    case readyTimeout
}

struct TerminalRestartCoordinator {
    let readyTimeout: Duration

    init(readyTimeout: Duration = .seconds(30)) {
        self.readyTimeout = readyTimeout
    }

    func restart(
        engine: any AgentEngine,
        workingDirectory: String,
        tool: String
    ) async -> Result<Void, TerminalRestartError> {
        engine.onProcessReady = nil

        if engine.engineState != .idle {
            engine.terminate()
            guard engine.engineState == .idle else {
                return .failure(.stopFailed)
            }
        }

        do {
            try engine.start(workingDirectory: workingDirectory, tool: tool)
        } catch {
            engine.onProcessReady = nil
            return .failure(.startFailed)
        }

        let signaled = await awaitReady(engine: engine)
        engine.onProcessReady = nil
        return signaled ? .success(()) : .failure(.readyTimeout)
    }

    private func awaitReady(engine: any AgentEngine) async -> Bool {
        let gate = ReadyGate()
        return await withCheckedContinuation { continuation in
            engine.onProcessReady = {
                guard gate.tryComplete() else { return }
                continuation.resume(returning: true)
            }
            let timeoutSeconds = Double(readyTimeout.components.seconds)
                + Double(readyTimeout.components.attoseconds) * 1e-18
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                guard gate.tryComplete() else { return }
                continuation.resume(returning: false)
            }
        }
    }
}

private final class ReadyGate: @unchecked Sendable {
    private var completed = false
    private let lock = NSLock()

    func tryComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}
