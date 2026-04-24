import Foundation

// MARK: - ProcessHandle

/// A cancellable handle to a running subprocess returned by `ProcessRunner.run`.
/// Callers use this to SIGTERM (then escalate to SIGKILL) the in-flight process.
protocol ProcessHandle: AnyObject {
    /// Sends SIGTERM, escalating to SIGKILL after a short grace period.
    func terminate()
    /// Sends SIGKILL immediately — for app-quit paths where the delayed escalation
    /// in `terminate()` may never fire because the dispatch queue dies with the app.
    func killImmediately()
}

// MARK: - ProcessRunner

/// Seam that spawns a single `claude -p /ralph` subprocess and delivers parsed
/// Stream-JSON Events plus a process-exit callback. Tests inject a fake
/// implementation; production uses `ClaudeProcessRunner`.
protocol ProcessRunner: AnyObject {
    /// Spawn a subprocess with `workingDirectory` as cwd.
    ///
    /// - `onEvent`: called on a background queue with the events decoded from
    ///   one stdout line via `StreamJsonDecoder`.
    /// - `onRawLine`: called on a background queue with each raw stdout line
    ///   before decoding (used by `IterationLogWriter` to tee to disk).
    /// - `onExit`: called on a background queue when the process exits, with
    ///   the process's exit status.
    ///
    /// - Returns: A `ProcessHandle` the caller may use to terminate the process.
    @discardableResult
    func run(
        workingDirectory: URL,
        progressDirectory: URL,
        effort: Effort,
        onEvent: @escaping ([IterationEvent]) -> Void,
        onRawLine: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> any ProcessHandle
}

// MARK: - ClaudeProcessRunner

/// Thin `ProcessRunner` wrapper that assembles Claude-specific argv and
/// delegates all subprocess plumbing to `SubprocessRunner`.
final class ClaudeProcessRunner: ProcessRunner {

    private let subprocess = SubprocessRunner()

    @discardableResult
    func run(
        workingDirectory: URL,
        progressDirectory: URL,
        effort: Effort,
        onEvent: @escaping ([IterationEvent]) -> Void,
        onRawLine: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> any ProcessHandle {
        let argv = [
            "claude", "-p",
            "--permission-mode", "acceptEdits",
            "--model", "sonnet",
            "--output-format", "stream-json",
            "--verbose",
            "--effort", effort.rawValue,
            "/ralph \(progressDirectory.path)"
        ]
        let decoder = StreamJsonDecoder()
        return subprocess.run(
            arguments: argv,
            workingDirectory: workingDirectory,
            decode: { decoder.decode($0) },
            onLaunch: { onRawLine("[effort] \(effort.rawValue)") },
            onEvent: onEvent,
            onRawLine: onRawLine,
            onExit: onExit
        )
    }
}

// MARK: - ProcessRunnerFactory

/// Error returned when the factory cannot produce a runner for the requested preset.
enum ProcessRunnerFactoryError: Error, Equatable {
    case unavailable(CLIPreset)
}

/// Creates a concrete `ProcessRunner` for a given `CLIPreset`.
/// Has no knowledge of Settings storage — callers resolve the preset before calling.
enum ProcessRunnerFactory {
    static func make(preset: CLIPreset) throws -> any ProcessRunner {
        switch preset {
        case .claude:
            return ClaudeProcessRunner()
        case .codex:
            return CodexProcessRunner()
        }
    }

    /// Returns a `TitleSynthesisBackend` for one-shot title generation using the given preset.
    static func makeTitleBackend(preset: CLIPreset) throws -> any TitleSynthesisBackend {
        switch preset {
        case .claude:
            return CLISubprocessTitleBackend(preset: preset)
        case .codex:
            throw ProcessRunnerFactoryError.unavailable(.codex)
        }
    }

    /// Returns the canonical tool identifier string for the given preset (e.g. `"cli/claude"`).
    /// Used by `EngineManager` to resolve the TerminalEngine tool for prompt-step dispatch.
    static func toolIdentifier(for preset: CLIPreset) -> String {
        "cli/\(preset.rawValue)"
    }
}

