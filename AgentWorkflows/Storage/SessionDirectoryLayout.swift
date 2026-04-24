import Foundation

/// Pure path-math for every artifact under a Session Directory.
/// No file-system I/O; all methods are deterministic functions of their inputs.
enum SessionDirectoryLayout {

    // MARK: - Session Directory

    /// `{workingDirectory}/.aw-cache/{sessionID}/`
    static func sessionDirectory(workingDirectory: URL, sessionID: UUID) -> URL {
        awCacheURL(workingDirectory: workingDirectory)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    // MARK: - Session Directory artifacts

    /// `{sessionDirectory}/state.json`
    static func stateFileURL(workingDirectory: URL, sessionID: UUID) -> URL {
        sessionDirectory(workingDirectory: workingDirectory, sessionID: sessionID)
            .appendingPathComponent("state.json")
    }

    /// `{sessionDirectory}/tasks.json`
    static func tasksFileURL(workingDirectory: URL, sessionID: UUID) -> URL {
        sessionDirectory(workingDirectory: workingDirectory, sessionID: sessionID)
            .appendingPathComponent("tasks.json")
    }

    /// `{sessionDirectory}/progress.txt`
    static func progressLogURL(workingDirectory: URL, sessionID: UUID) -> URL {
        sessionDirectory(workingDirectory: workingDirectory, sessionID: sessionID)
            .appendingPathComponent("progress.txt")
    }

    /// `{sessionDirectory}/events.jsonl`
    static func eventsLogURL(workingDirectory: URL, sessionID: UUID) -> URL {
        sessionDirectory(workingDirectory: workingDirectory, sessionID: sessionID)
            .appendingPathComponent("events.jsonl")
    }

    /// `{sessionDirectory}/ralph-logs/`
    static func iterationLogsDirectoryURL(workingDirectory: URL, sessionID: UUID) -> URL {
        sessionDirectory(workingDirectory: workingDirectory, sessionID: sessionID)
            .appendingPathComponent("ralph-logs", isDirectory: true)
    }

    /// `{sessionDirectory}/step-complete-{sessionID}`
    static func signalFileURL(workingDirectory: URL, sessionID: UUID) -> URL {
        sessionDirectory(workingDirectory: workingDirectory, sessionID: sessionID)
            .appendingPathComponent("step-complete-\(sessionID.uuidString)")
    }

    // MARK: - .aw-cache root artifacts

    /// `{workingDirectory}/.aw-cache/`
    static func awCacheURL(workingDirectory: URL) -> URL {
        workingDirectory.appendingPathComponent(".aw-cache", isDirectory: true)
    }

    /// `{workingDirectory}/.aw-cache/.gitignore`
    static func gitignoreURL(workingDirectory: URL) -> URL {
        awCacheURL(workingDirectory: workingDirectory)
            .appendingPathComponent(".gitignore")
    }
}
