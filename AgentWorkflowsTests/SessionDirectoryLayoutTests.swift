import Testing
import Foundation
@testable import AgentWorkflows

@Suite("SessionDirectoryLayout")
struct SessionDirectoryLayoutTests {

    private let workingDirectory = URL(fileURLWithPath: "/repos/my-project")
    private let sessionID = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!

    // MARK: - .aw-cache root

    @Test func awCacheURLIsUnderWorkingDirectory() {
        let url = SessionDirectoryLayout.awCacheURL(workingDirectory: workingDirectory)
        #expect(url.path == "/repos/my-project/.aw-cache")
    }

    @Test func gitignoreURLIsInsideAwCache() {
        let url = SessionDirectoryLayout.gitignoreURL(workingDirectory: workingDirectory)
        #expect(url.path == "/repos/my-project/.aw-cache/.gitignore")
    }

    // MARK: - Session Directory

    @Test func sessionDirectoryIsAwCacheScopedByUUID() {
        let url = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: workingDirectory,
            sessionID: sessionID
        )
        #expect(url.path == "/repos/my-project/.aw-cache/12345678-1234-1234-1234-123456789012")
    }

    // MARK: - Session artifacts

    @Test func stateFileURLIsInsideSessionDirectory() {
        let url = SessionDirectoryLayout.stateFileURL(
            workingDirectory: workingDirectory,
            sessionID: sessionID
        )
        #expect(url.path == "/repos/my-project/.aw-cache/12345678-1234-1234-1234-123456789012/state.json")
    }

    @Test func tasksFileURLIsInsideSessionDirectory() {
        let url = SessionDirectoryLayout.tasksFileURL(
            workingDirectory: workingDirectory,
            sessionID: sessionID
        )
        #expect(url.path == "/repos/my-project/.aw-cache/12345678-1234-1234-1234-123456789012/tasks.json")
    }

    @Test func canvasFileURLIsInsideSessionDirectory() {
        let url = SessionDirectoryLayout.canvasFileURL(
            workingDirectory: workingDirectory,
            sessionID: sessionID
        )
        #expect(url.path == "/repos/my-project/.aw-cache/12345678-1234-1234-1234-123456789012/canvas.toml")
    }

    @Test func canvasLayoutFileURLIsInsideSessionDirectory() {
        let url = SessionDirectoryLayout.canvasLayoutFileURL(
            workingDirectory: workingDirectory,
            sessionID: sessionID
        )
        #expect(url.path == "/repos/my-project/.aw-cache/12345678-1234-1234-1234-123456789012/canvas-layout.toml")
    }

    @Test func symbolIndexFileURLIsInsideSessionDirectory() {
        let url = SessionDirectoryLayout.symbolIndexFileURL(
            workingDirectory: workingDirectory,
            sessionID: sessionID
        )
        #expect(url.path == "/repos/my-project/.aw-cache/12345678-1234-1234-1234-123456789012/symbol-index.toml")
    }

    @Test func architectureFileURLIsInsideSessionDirectory() {
        let url = SessionDirectoryLayout.architectureFileURL(
            workingDirectory: workingDirectory,
            sessionID: sessionID
        )
        #expect(url.path == "/repos/my-project/.aw-cache/12345678-1234-1234-1234-123456789012/ARCHITECTURE.toml")
    }

    @Test func eventsLogURLIsInsideSessionDirectory() {
        let url = SessionDirectoryLayout.eventsLogURL(
            workingDirectory: workingDirectory,
            sessionID: sessionID
        )
        #expect(url.path == "/repos/my-project/.aw-cache/12345678-1234-1234-1234-123456789012/events.jsonl")
    }

    @Test func iterationLogsDirectoryURLIsInsideSessionDirectory() {
        let url = SessionDirectoryLayout.iterationLogsDirectoryURL(
            workingDirectory: workingDirectory,
            sessionID: sessionID
        )
        #expect(url.path == "/repos/my-project/.aw-cache/12345678-1234-1234-1234-123456789012/ralph-logs")
    }

    @Test func signalFileURLContainsSessionIDSuffix() {
        let url = SessionDirectoryLayout.signalFileURL(
            workingDirectory: workingDirectory,
            sessionID: sessionID
        )
        #expect(url.path == "/repos/my-project/.aw-cache/12345678-1234-1234-1234-123456789012/step-complete-12345678-1234-1234-1234-123456789012")
    }

    // MARK: - Independence from working directory value

    @Test func differentWorkingDirectoriesProduceDifferentPaths() {
        let dir1 = URL(fileURLWithPath: "/repos/project-a")
        let dir2 = URL(fileURLWithPath: "/repos/project-b")
        let url1 = SessionDirectoryLayout.sessionDirectory(workingDirectory: dir1, sessionID: sessionID)
        let url2 = SessionDirectoryLayout.sessionDirectory(workingDirectory: dir2, sessionID: sessionID)
        #expect(url1 != url2)
    }

    @Test func differentSessionIDsProduceDifferentPaths() {
        let id2 = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let url1 = SessionDirectoryLayout.sessionDirectory(workingDirectory: workingDirectory, sessionID: sessionID)
        let url2 = SessionDirectoryLayout.sessionDirectory(workingDirectory: workingDirectory, sessionID: id2)
        #expect(url1 != url2)
    }

    // MARK: - Session Directory is a prefix of all artifact URLs

    @Test func allArtifactURLsAreUnderSessionDirectory() {
        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: workingDirectory,
            sessionID: sessionID
        ).path + "/"

        let artifacts = [
            SessionDirectoryLayout.stateFileURL(workingDirectory: workingDirectory, sessionID: sessionID),
            SessionDirectoryLayout.tasksFileURL(workingDirectory: workingDirectory, sessionID: sessionID),
            SessionDirectoryLayout.eventsLogURL(workingDirectory: workingDirectory, sessionID: sessionID),
            SessionDirectoryLayout.iterationLogsDirectoryURL(workingDirectory: workingDirectory, sessionID: sessionID),
            SessionDirectoryLayout.signalFileURL(workingDirectory: workingDirectory, sessionID: sessionID),
        ]

        for url in artifacts {
            #expect(url.path.hasPrefix(sessionDir), "Expected \(url.path) to be under \(sessionDir)")
        }
    }
}
