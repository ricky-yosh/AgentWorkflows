import Testing
import Foundation
@testable import AgentWorkflows

// MARK: - Session Deletion Tests

/// End-to-end tests for session deletion (task #5):
/// - Remove Session Directory from working directory
/// - Remove registry entry from sessions.json
/// - Skip unreachable directories silently
struct SessionDeletionTests {

    private let testBase: URL
    private let testWorkingDir: URL
    private let registryURL: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AW-Deletion-Tests-\(UUID().uuidString)")
        testBase = base
        testWorkingDir = base.appendingPathComponent("project")
        registryURL = base.appendingPathComponent("sessions.json")
        try FileManager.default.createDirectory(at: testWorkingDir, withIntermediateDirectories: true)
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: testBase)
    }

    private func makeStore() -> SessionStore {
        SessionStore(registryURL: registryURL)
    }

    private func sessionDir(for session: Session) -> URL {
        SessionDirectoryLayout.sessionDirectory(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: session.id
        )
    }

    // MARK: - Happy Path: Full Cleanup

    @Test func deleteRemovesSessionDirectory() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(workingDirectory: testWorkingDir.path,
                                               workflowName: "Blank Workflow")
        #expect(FileManager.default.fileExists(atPath: sessionDir(for: session).path))

        try store.deleteSession(session)
        #expect(!FileManager.default.fileExists(atPath: sessionDir(for: session).path))
    }

    @Test func deleteRemovesFromInMemoryList() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(workingDirectory: testWorkingDir.path,
                                               workflowName: "Blank Workflow")
        #expect(store.sessions.count == 1)

        try store.deleteSession(session)
        #expect(store.sessions.isEmpty)
    }

    @Test func deleteRemovesRegistryEntry() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(workingDirectory: testWorkingDir.path,
                                               workflowName: "Blank Workflow")
        try store.deleteSession(session)

        let entries = try SessionRegistry(fileURL: registryURL).load()
        #expect(!entries.contains(where: { $0.id == session.id }))
    }

    @Test func deleteLeavesGitignoreAndAwCacheIntact() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(workingDirectory: testWorkingDir.path,
                                               workflowName: "Blank Workflow")
        let awCache = SessionDirectoryLayout.awCacheURL(workingDirectory: testWorkingDir)
        #expect(FileManager.default.fileExists(atPath: awCache.path))

        try store.deleteSession(session)

        // .aw-cache/ itself and .gitignore remain; only the session UUID directory is removed
        #expect(FileManager.default.fileExists(atPath: awCache.path))
    }

    @Test func deleteSecondSessionLeavesFirstIntact() throws {
        defer { cleanup() }
        let store = makeStore()
        let session1 = try store.createSession(workingDirectory: testWorkingDir.path,
                                                workflowName: "W")
        let session2 = try store.createSession(workingDirectory: testWorkingDir.path,
                                                workflowName: "W")

        try store.deleteSession(session1)

        #expect(store.sessions.count == 1)
        #expect(store.sessions.contains(where: { $0.id == session2.id }))
        #expect(!FileManager.default.fileExists(atPath: sessionDir(for: session1).path))
        #expect(FileManager.default.fileExists(atPath: sessionDir(for: session2).path))
    }

    // MARK: - Unreachable Paths (Best-Effort)

    @Test func deleteSessionWhenDirectoryAlreadyRemoved() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(workingDirectory: testWorkingDir.path,
                                               workflowName: "W")

        try FileManager.default.removeItem(at: sessionDir(for: session))

        try store.deleteSession(session)
        #expect(store.sessions.isEmpty)
    }

    @Test func deletePhantomSessionNotInStoreDoesNotThrow() throws {
        defer { cleanup() }
        let store = makeStore()
        let phantom = Session(
            id: UUID(),
            name: "Ghost",
            workingDirectory: testWorkingDir.path,
            workflowName: "Blank",
            state: .idle,
            currentPhaseIndex: 0,
            currentStepIndex: 0,
            completedStepIDs: []
        )

        try store.deleteSession(phantom)
        #expect(store.sessions.isEmpty)
    }

    @Test func deleteSessionWithUnreachableWorkingDirectory() throws {
        defer { cleanup() }
        let fakeWorkDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AW-Nonexistent-\(UUID().uuidString)")
            .appendingPathComponent("project")

        let id = UUID()
        let session = Session(
            id: id,
            name: "Unreachable",
            workingDirectory: fakeWorkDir.path,
            workflowName: "Blank",
            state: .idle,
            currentPhaseIndex: 0,
            currentStepIndex: 0,
            completedStepIDs: []
        )

        let store = makeStore()
        try store.deleteSession(session)
        #expect(store.sessions.isEmpty)
    }

    // MARK: - Multiple Sessions in Same Working Directory

    @Test func deleteOneOfManySameDirectorySessionsKeepsOthers() throws {
        defer { cleanup() }
        let store = makeStore()
        let session1 = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "W")
        let session2 = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "W")
        let session3 = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "W")

        #expect(store.sessions.count == 3)

        try store.deleteSession(session2)

        #expect(store.sessions.count == 2)
        #expect(store.sessions.contains(where: { $0.id == session1.id }))
        #expect(!store.sessions.contains(where: { $0.id == session2.id }))
        #expect(store.sessions.contains(where: { $0.id == session3.id }))

        #expect(FileManager.default.fileExists(atPath: sessionDir(for: session1).path))
        #expect(FileManager.default.fileExists(atPath: sessionDir(for: session3).path))
        #expect(!FileManager.default.fileExists(atPath: sessionDir(for: session2).path))
    }

    // MARK: - State Preservation: Other Sessions Unaffected

    @Test func deleteRunningSessionCleansUp() throws {
        defer { cleanup() }
        let store = makeStore()
        var session = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "W")
        session.state = .running
        try store.saveSession(session)

        try store.deleteSession(session)
        #expect(store.sessions.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sessionDir(for: session).path))
    }

    @Test func deleteSessionWithCompletedStepsRemovesAllData() throws {
        defer { cleanup() }
        let store = makeStore()
        var session = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "W")
        session.currentPhaseIndex = 2
        session.currentStepIndex = 4
        session.completedStepIDs = ["step-1", "step-2", "step-3", "step-4"]
        try store.saveSession(session)

        let dir = sessionDir(for: session)
        try "task data".write(to: dir.appendingPathComponent("tasks.json"), atomically: true, encoding: .utf8)

        try store.deleteSession(session)

        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }
}
