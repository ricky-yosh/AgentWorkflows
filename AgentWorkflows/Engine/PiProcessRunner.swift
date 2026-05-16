import Foundation

// MARK: - PiProcessRunner

/// Thin `ProcessRunner` wrapper that assembles Pi-specific argv and
/// delegates all subprocess plumbing to `SubprocessRunner`.
final class PiProcessRunner: ProcessRunner {

    typealias RunSubprocess = (
        _ arguments: [String],
        _ workingDirectory: URL,
        _ decode: @escaping (String) -> [IterationEvent],
        _ onLaunch: (() -> Void)?,
        _ onEvent: @escaping ([IterationEvent]) -> Void,
        _ onRawLine: @escaping (String) -> Void,
        _ onExit: @escaping (Int32) -> Void
    ) -> any ProcessHandle

    private let runSubprocess: RunSubprocess

    init(subprocess: SubprocessRunner = SubprocessRunner()) {
        self.runSubprocess = { arguments, workingDirectory, decode, onLaunch, onEvent, onRawLine, onExit in
            subprocess.run(
                arguments: arguments,
                workingDirectory: workingDirectory,
                decode: decode,
                onLaunch: onLaunch,
                onEvent: onEvent,
                onRawLine: onRawLine,
                onExit: onExit
            )
        }
    }

    init(runSubprocess: @escaping RunSubprocess) {
        self.runSubprocess = runSubprocess
    }

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
            "pi", "-p",
            "--mode", "json",
            "/skill:ralph \(progressDirectory.path)"
        ]

        let decoder = PiEventDecoder()

        return runSubprocess(
            argv,
            workingDirectory,
            { decoder.decode($0) },
            { onRawLine("[effort] \(effort.rawValue)") },
            onEvent,
            onRawLine,
            onExit
        )
    }
}
