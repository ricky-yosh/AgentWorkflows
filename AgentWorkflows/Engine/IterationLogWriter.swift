import Foundation

/// Tees raw stdout lines from a `ProcessRunner` subprocess into per-iteration
/// log files at `{progressDirectory}/ralph-logs/iter-{N}.log`.
///
/// Each `open(iteration:)` call creates a fresh file (truncating any prior run
/// at that number). `append(_:)` writes one line and syncs to disk so a crash
/// mid-iteration still leaves a readable prefix.
final class IterationLogWriter {

    private let logsDirectory: URL
    private var fileHandle: FileHandle?

    init(progressDirectory: URL) {
        logsDirectory = progressDirectory.appending(path: "ralph-logs", directoryHint: .isDirectory)
    }

    /// Creates the `ralph-logs/` subdirectory if absent, then opens
    /// `iter-{iteration}.log` for writing (truncating any existing file).
    func open(iteration: Int) throws {
        close()
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let logURL = logsDirectory.appending(path: "iter-\(iteration).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: logURL)
    }

    /// Appends `line` plus a newline and synchronises to disk.
    func append(_ line: String) {
        guard let fh = fileHandle else { return }
        var output = line
        output.append("\n")
        guard let data = output.data(using: .utf8) else { return }
        fh.write(data)
        fh.synchronizeFile()
    }

    /// Closes the underlying file handle.
    func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}
