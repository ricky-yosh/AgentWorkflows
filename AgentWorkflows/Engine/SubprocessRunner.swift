import Foundation
import Darwin

// MARK: - SubprocessHandle

final class SubprocessHandle: ProcessHandle {
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        let process = self.process
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            guard process.isRunning else { return }
            Darwin.kill(pid, SIGKILL)
        }
    }

    func killImmediately() {
        let pid = process.processIdentifier
        guard pid > 0 else { return }
        Darwin.kill(pid, SIGKILL)
    }
}

// MARK: - SubprocessRunner

/// Internal helper that owns the shared spawn/pipe/termination plumbing reused
/// by `ClaudeProcessRunner`, `CodexProcessRunner`, and any future CLI wrapper.
/// Not exposed outside the engine layer.
final class SubprocessRunner {

    private static var pathPrefix: String {
        let home = NSHomeDirectory()
        return "\(home)/.opencode/bin:\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }

    /// Spawns `/usr/bin/env <arguments>` with `workingDirectory` as cwd.
    ///
    /// - `decode`: maps one stdout line to zero or more `IterationEvent`s.
    /// - `onLaunch`: called synchronously after successful `process.run()`.
    /// - `onEvent`: called on a background queue when `decode` produces events.
    /// - `onRawLine`: called on a background queue with each raw stdout line and
    ///   stderr line (prefixed with `[stderr]`) before decoding.
    /// - `onExit`: called on a background queue when the process exits.
    @discardableResult
    func run(
        arguments: [String],
        workingDirectory: URL,
        decode: @escaping (String) -> [IterationEvent],
        onLaunch: (() -> Void)? = nil,
        onEvent: @escaping ([IterationEvent]) -> Void,
        onRawLine: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> any ProcessHandle {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"] ?? ""
        env["PATH"] = existing.isEmpty
            ? Self.pathPrefix
            : "\(Self.pathPrefix):\(existing)"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        let errPipe = Pipe()
        process.standardError = errPipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            for line in chunk.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .newlines)
                guard !trimmed.isEmpty else { continue }
                onRawLine(trimmed)
                let events = decode(trimmed)
                if !events.isEmpty { onEvent(events) }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            for line in chunk.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .newlines)
                guard !trimmed.isEmpty else { continue }
                onRawLine("[stderr] \(trimmed)")
            }
        }

        process.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            onRawLine("[exit] \(p.terminationStatus)")
            onExit(p.terminationStatus)
        }

        let handle = SubprocessHandle(process: process)
        do {
            try process.run()
            onLaunch?()
        } catch {
            onExit(-1)
        }
        return handle
    }
}
