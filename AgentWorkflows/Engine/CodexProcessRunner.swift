import Foundation

// MARK: - CodexProcessRunner

/// Thin `ProcessRunner` wrapper that assembles Codex-specific argv and
/// delegates all subprocess plumbing to `SubprocessRunner`.
final class CodexProcessRunner: ProcessRunner {

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
            "codex", "exec",
            "--dangerously-bypass-approvals-and-sandbox",
            "-c", "model_reasoning_effort=\(effort.rawValue)",
            "--json",
            "$ralph \(progressDirectory.path)"
        ]
        let decoder = CodexEventDecoder()
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
