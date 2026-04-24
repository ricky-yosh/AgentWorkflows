import Testing
import Foundation
@testable import AgentWorkflows

// MARK: - Fake StateFileWatcher

final class FakeStateFileWatcher: StateFileWatcher {
    var onChange: (() -> Void)?
    private(set) var isWatching = false
    private(set) var watchedURL: URL?

    func start(watching fileURL: URL) {
        isWatching = true
        watchedURL = fileURL
    }

    func stop() {
        isWatching = false
    }

    func simulateWrite() {
        onChange?()
    }
}

// MARK: - SessionStore Tests

/// All tests use a temporary directory to avoid touching the real Application Support path.
/// SessionStore accepts a custom registryURL and writes sessions into each session's
/// working directory under .aw-cache/{sessionID}/.
struct SessionStoreTests {

    private let testBase: URL
    private let testWorkingDir: URL
    private let registryURL: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AW-Tests-\(UUID().uuidString)")
        testBase = base
        testWorkingDir = base.appendingPathComponent("project")
        registryURL = base.appendingPathComponent("sessions.json")
        try FileManager.default.createDirectory(at: testWorkingDir, withIntermediateDirectories: true)
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: testBase)
    }

    private func makeStore(watcherFactory: @escaping () -> any StateFileWatcher = { FakeStateFileWatcher() }) -> SessionStore {
        SessionStore(registryURL: registryURL, watcherFactory: watcherFactory)
    }

    // MARK: - Initialization / Scanning

    @Test func initWithEmptyRegistryHasNoSessions() throws {
        defer { cleanup() }
        let store = makeStore()
        #expect(store.sessions.isEmpty)
    }

    @Test func initScansExistingSessionsViaRegistry() throws {
        defer { cleanup() }
        let id1 = UUID()
        let id2 = UUID()
        for (id, name) in [(id1, "Session A"), (id2, "Session B")] {
            let session = Session(
                id: id,
                name: name,
                workingDirectory: testWorkingDir.path,
                workflowName: "AW Greenfield",
                state: .idle,
                currentPhaseIndex: 0,
                currentStepIndex: 0,
                completedStepIDs: []
            )
            let workingDir = URL(fileURLWithPath: session.workingDirectory)
            let sessionDir = SessionDirectoryLayout.sessionDirectory(workingDirectory: workingDir, sessionID: id)
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(session)
            try data.write(to: SessionDirectoryLayout.stateFileURL(workingDirectory: workingDir, sessionID: id))
            let entry = SessionRegistryEntry(id: id, name: name,
                                             workingDirectory: testWorkingDir.path,
                                             workflowName: "AW Greenfield")
            try SessionRegistry(fileURL: registryURL).add(entry)
        }

        let store = makeStore()
        #expect(store.sessions.count == 2)

        let names = Set(store.sessions.map(\.name))
        #expect(names.contains("Session A"))
        #expect(names.contains("Session B"))
    }

    @Test func initSkipsUnreachableRegistryEntries() throws {
        defer { cleanup() }
        let id = UUID()
        let fakeWorkDir = "/nonexistent-path-\(UUID().uuidString)"
        let entry = SessionRegistryEntry(id: id, name: "Ghost",
                                         workingDirectory: fakeWorkDir,
                                         workflowName: "W")
        try SessionRegistry(fileURL: registryURL).add(entry)

        let store = makeStore()
        #expect(store.sessions.isEmpty)
    }

    @Test func initSkipsReachableEntriesWithoutStateJSON() throws {
        defer { cleanup() }
        let id = UUID()
        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: testWorkingDir, sessionID: id)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let entry = SessionRegistryEntry(id: id, name: "No State",
                                         workingDirectory: testWorkingDir.path,
                                         workflowName: "W")
        try SessionRegistry(fileURL: registryURL).add(entry)

        let store = makeStore()
        #expect(store.sessions.isEmpty)
    }

    @Test func initSkipsCorruptStateJSON() throws {
        defer { cleanup() }
        let id = UUID()
        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: testWorkingDir, sessionID: id)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(
            to: SessionDirectoryLayout.stateFileURL(workingDirectory: testWorkingDir, sessionID: id))
        let entry = SessionRegistryEntry(id: id, name: "Corrupt",
                                         workingDirectory: testWorkingDir.path,
                                         workflowName: "W")
        try SessionRegistry(fileURL: registryURL).add(entry)

        let store = makeStore()
        #expect(store.sessions.isEmpty)
    }

    // MARK: - Create Session

    @Test func createSessionWritesStateJSON() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: testWorkingDir,
            sessionID: session.id
        )
        #expect(FileManager.default.fileExists(atPath: stateFile.path))
    }

    @Test func createSessionReturnsCorrectModel() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        #expect(session.name.hasPrefix("Untitled — "))
        #expect(session.workingDirectory == testWorkingDir.path)
        #expect(session.workflowName == "AW Greenfield")
        #expect(session.state == .idle)
        #expect(session.currentPhaseIndex == 0)
        #expect(session.currentStepIndex == 0)
        #expect(session.completedStepIDs.isEmpty)
    }

    @Test func createSessionAssignsPlaceholderName() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        #expect(session.name.hasPrefix("Untitled — "))
        #expect(!session.name.isEmpty)

        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: testWorkingDir,
            sessionID: session.id
        )
        let decoded = try JSONDecoder().decode(Session.self, from: Data(contentsOf: stateFile))
        #expect(decoded.name == session.name)
    }

    @Test func createSessionAddsToSessionsList() throws {
        defer { cleanup() }
        let store = makeStore()
        #expect(store.sessions.isEmpty)

        _ = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "Blank Workflow"
        )
        #expect(store.sessions.count == 1)

        _ = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "Blank Workflow"
        )
        #expect(store.sessions.count == 2)
    }

    @Test func createSessionCreatesSessionDirectory() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: testWorkingDir,
            sessionID: session.id
        )
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: sessionDir.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test func createSessionWritesGitignore() throws {
        defer { cleanup() }
        let store = makeStore()
        _ = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        let gitignore = SessionDirectoryLayout.gitignoreURL(workingDirectory: testWorkingDir)
        let content = try String(contentsOf: gitignore, encoding: .utf8)
        #expect(content == "*")
    }

    @Test func createSessionDoesNotOverwriteExistingGitignore() throws {
        defer { cleanup() }
        let awCache = SessionDirectoryLayout.awCacheURL(workingDirectory: testWorkingDir)
        try FileManager.default.createDirectory(at: awCache, withIntermediateDirectories: true)
        let gitignore = SessionDirectoryLayout.gitignoreURL(workingDirectory: testWorkingDir)
        try "custom".write(to: gitignore, atomically: true, encoding: .utf8)

        let store = makeStore()
        _ = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        let content = try String(contentsOf: gitignore, encoding: .utf8)
        #expect(content == "custom")
    }

    @Test func createSessionAddsRegistryEntry() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        let entries = try SessionRegistry(fileURL: registryURL).load()
        #expect(entries.contains(where: { $0.id == session.id }))
        let entry = entries.first(where: { $0.id == session.id })
        #expect(entry?.workingDirectory == testWorkingDir.path)
    }

    @Test func createSessionWritesDecodableStateJSON() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: testWorkingDir,
            sessionID: session.id
        )
        let data = try Data(contentsOf: stateFile)
        let decoded = try JSONDecoder().decode(Session.self, from: data)

        #expect(decoded.id == session.id)
        #expect(decoded.name.hasPrefix("Untitled — "))
        #expect(decoded.state == .idle)
    }

    // MARK: - Save Session

    @Test func saveSessionUpdatesStateJSON() throws {
        defer { cleanup() }
        let store = makeStore()
        var session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        session.state = .running
        session.currentPhaseIndex = 1
        session.currentStepIndex = 3
        session.completedStepIDs = ["step-a", "step-b"]
        try store.saveSession(session)

        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: testWorkingDir,
            sessionID: session.id
        )
        let data = try Data(contentsOf: stateFile)
        let decoded = try JSONDecoder().decode(Session.self, from: data)

        #expect(decoded.state == .running)
        #expect(decoded.currentPhaseIndex == 1)
        #expect(decoded.currentStepIndex == 3)
        #expect(decoded.completedStepIDs == ["step-a", "step-b"])
    }

    @Test func saveSessionUpdatesInMemoryList() throws {
        defer { cleanup() }
        let store = makeStore()
        var session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        session.state = .paused
        try store.saveSession(session)

        let found = store.sessions.first(where: { $0.id == session.id })
        #expect(found?.state == .paused)
    }

    // MARK: - Delete Session

    @Test func deleteSessionRemovesDirectory() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: testWorkingDir,
            sessionID: session.id
        )
        #expect(FileManager.default.fileExists(atPath: sessionDir.path))

        try store.deleteSession(session)
        #expect(!FileManager.default.fileExists(atPath: sessionDir.path))
    }

    @Test func deleteSessionRemovesFromSessionsList() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        #expect(store.sessions.count == 1)
        try store.deleteSession(session)
        #expect(store.sessions.isEmpty)
    }

    @Test func deleteSessionRemovesRegistryEntry() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )

        try store.deleteSession(session)

        let entries = try SessionRegistry(fileURL: registryURL).load()
        #expect(!entries.contains(where: { $0.id == session.id }))
    }

    @Test func deleteNonexistentSessionDoesNotThrow() throws {
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
    }

    // MARK: - Round Trip (create → save → reload)

    @Test func fullRoundTrip() throws {
        defer { cleanup() }
        let store1 = makeStore()
        var session = try store1.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )
        let originalName = session.name
        session.state = .paused
        session.currentPhaseIndex = 2
        session.currentStepIndex = 1
        session.completedStepIDs = ["s1", "s2", "s3"]
        try store1.saveSession(session)

        let store2 = makeStore()
        #expect(store2.sessions.count == 1)

        let reloaded = store2.sessions[0]
        #expect(reloaded.id == session.id)
        #expect(reloaded.name == originalName)
        #expect(reloaded.workingDirectory == testWorkingDir.path)
        #expect(reloaded.workflowName == "AW Greenfield")
        #expect(reloaded.state == .paused)
        #expect(reloaded.currentPhaseIndex == 2)
        #expect(reloaded.currentStepIndex == 1)
        #expect(reloaded.completedStepIDs == ["s1", "s2", "s3"])
    }

    // MARK: - Edge Cases

    @Test func multipleSessionsCreateDistinctDirectories() throws {
        defer { cleanup() }
        let store = makeStore()
        let s1 = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "W")
        let s2 = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "W")

        #expect(s1.id != s2.id)

        let dir1 = SessionDirectoryLayout.sessionDirectory(workingDirectory: testWorkingDir, sessionID: s1.id)
        let dir2 = SessionDirectoryLayout.sessionDirectory(workingDirectory: testWorkingDir, sessionID: s2.id)
        #expect(FileManager.default.fileExists(atPath: dir1.path))
        #expect(FileManager.default.fileExists(atPath: dir2.path))
    }

    @Test func multiplePlaceholderSessionsGetDistinctIDs() throws {
        defer { cleanup() }
        let store = makeStore()
        let s1 = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "W")
        let s2 = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "W")

        #expect(s1.id != s2.id)
        #expect(store.sessions.count == 2)
    }

    // MARK: - Braindump

    @Test func writeBraindumpCreatesFile() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "AW Greenfield")

        try store.writeBraindump(sessionID: session.id, text: "my braindump")

        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: testWorkingDir, sessionID: session.id)
        let braindumpFile = sessionDir.appendingPathComponent("braindump.md")
        let content = try String(contentsOf: braindumpFile, encoding: .utf8)
        #expect(content == "my braindump")
    }

    @Test func writeBraindumpDoesNotOverwriteExistingFile() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "AW Greenfield")

        try store.writeBraindump(sessionID: session.id, text: "first")
        try store.writeBraindump(sessionID: session.id, text: "second")

        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: testWorkingDir, sessionID: session.id)
        let braindumpFile = sessionDir.appendingPathComponent("braindump.md")
        let content = try String(contentsOf: braindumpFile, encoding: .utf8)
        #expect(content == "first")
    }

    // MARK: - Rename

    @Test func renameManualUpdatesNameAndSetsFlag() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "AW Greenfield")

        try store.rename(sessionID: session.id, to: "My Feature", manual: true)

        let inMemory = store.sessions.first(where: { $0.id == session.id })
        #expect(inMemory?.name == "My Feature")
        #expect(inMemory?.manuallyTitled == true)

        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: testWorkingDir, sessionID: session.id)
        let decoded = try JSONDecoder().decode(Session.self, from: Data(contentsOf: stateFile))
        #expect(decoded.name == "My Feature")
        #expect(decoded.manuallyTitled == true)
    }

    @Test func renameSynthesisIsNoOpWhenManuallyTitled() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "AW Greenfield")

        try store.rename(sessionID: session.id, to: "My Override", manual: true)
        try store.rename(sessionID: session.id, to: "Synthesized Title", manual: false)

        let inMemory = store.sessions.first(where: { $0.id == session.id })
        #expect(inMemory?.name == "My Override")
        #expect(inMemory?.manuallyTitled == true)

        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: testWorkingDir, sessionID: session.id)
        let decoded = try JSONDecoder().decode(Session.self, from: Data(contentsOf: stateFile))
        #expect(decoded.name == "My Override")
    }

    @Test func renameSynthesisUpdatesWhenNotManuallyTitled() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "AW Greenfield")

        try store.rename(sessionID: session.id, to: "Auto Title", manual: false)

        let inMemory = store.sessions.first(where: { $0.id == session.id })
        #expect(inMemory?.name == "Auto Title")
        #expect(inMemory?.manuallyTitled == false)

        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: testWorkingDir, sessionID: session.id)
        let decoded = try JSONDecoder().decode(Session.self, from: Data(contentsOf: stateFile))
        #expect(decoded.name == "Auto Title")
        #expect(decoded.manuallyTitled == false)
    }

    @Test func renameUpdatesRegistryEntry() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "AW Greenfield")

        try store.rename(sessionID: session.id, to: "Registry Name", manual: true)

        let entries = try SessionRegistry(fileURL: registryURL).load()
        let entry = entries.first(where: { $0.id == session.id })
        #expect(entry?.name == "Registry Name")
    }

    // MARK: - StateFileWatcher Integration

    @Test func externalEditToStateJSONRefreshesInMemorySession() throws {
        defer { cleanup() }
        var createdWatchers: [FakeStateFileWatcher] = []
        let store = SessionStore(registryURL: registryURL) {
            let w = FakeStateFileWatcher()
            createdWatchers.append(w)
            return w
        }

        let session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )
        #expect(store.sessions.first(where: { $0.id == session.id })?.state == .idle)

        var modified = session
        modified.name = "Externally Renamed"
        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: testWorkingDir, sessionID: session.id)
        try JSONEncoder().encode(modified).write(to: stateFile)

        let watcher = try #require(createdWatchers.last)
        watcher.simulateWrite()

        let inMemory = store.sessions.first(where: { $0.id == session.id })
        #expect(inMemory?.name == "Externally Renamed")
    }

    @Test func deleteSessionDetachesWatcherAndPreventsCallback() throws {
        defer { cleanup() }
        var createdWatchers: [FakeStateFileWatcher] = []
        let store = SessionStore(registryURL: registryURL) {
            let w = FakeStateFileWatcher()
            createdWatchers.append(w)
            return w
        }

        let session = try store.createSession(
            workingDirectory: testWorkingDir.path,
            workflowName: "AW Greenfield"
        )
        let watcher = try #require(createdWatchers.last)
        #expect(watcher.isWatching)

        try store.deleteSession(session)

        #expect(!watcher.isWatching)

        watcher.simulateWrite()
        #expect(!store.sessions.contains(where: { $0.id == session.id }))
    }

    @Test func scanSessionsAttachesWatcherPerDiscoveredSession() throws {
        defer { cleanup() }
        for name in ["Session A", "Session B"] {
            let id = UUID()
            let session = Session(
                id: id,
                name: name,
                workingDirectory: testWorkingDir.path,
                workflowName: "AW Greenfield",
                state: .idle,
                currentPhaseIndex: 0,
                currentStepIndex: 0,
                completedStepIDs: []
            )
            let workingDir = URL(fileURLWithPath: session.workingDirectory)
            let sessionDir = SessionDirectoryLayout.sessionDirectory(workingDirectory: workingDir, sessionID: id)
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            try JSONEncoder().encode(session).write(
                to: SessionDirectoryLayout.stateFileURL(workingDirectory: workingDir, sessionID: id))
            let entry = SessionRegistryEntry(id: id, name: name,
                                             workingDirectory: testWorkingDir.path,
                                             workflowName: "AW Greenfield")
            try SessionRegistry(fileURL: registryURL).add(entry)
        }

        var watcherCount = 0
        let store = SessionStore(registryURL: registryURL) {
            watcherCount += 1
            return FakeStateFileWatcher()
        }

        #expect(store.sessions.count == 2)
        #expect(watcherCount == 2)
    }

    @Test func renameDoesNotMoveSessionDirectory() throws {
        defer { cleanup() }
        let store = makeStore()
        let session = try store.createSession(workingDirectory: testWorkingDir.path, workflowName: "AW Greenfield")

        try store.rename(sessionID: session.id, to: "New Name", manual: true)

        // Session directory still exists at UUID path, not at new name
        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: testWorkingDir, sessionID: session.id)
        #expect(FileManager.default.fileExists(atPath: sessionDir.path))

        // In-memory name is updated
        let inMemory = store.sessions.first(where: { $0.id == session.id })
        #expect(inMemory?.name == "New Name")
    }

    // MARK: - Missing Sessions

    @Test func initPopulatesMissingSessionsForUnreachableEntries() throws {
        defer { cleanup() }
        let id = UUID()
        let fakeWorkDir = "/nonexistent-path-\(UUID().uuidString)"
        let entry = SessionRegistryEntry(id: id, name: "Ghost",
                                         workingDirectory: fakeWorkDir,
                                         workflowName: "W")
        try SessionRegistry(fileURL: registryURL).add(entry)

        let store = makeStore()
        #expect(store.sessions.isEmpty)
        #expect(store.missingSessions.count == 1)
        #expect(store.missingSessions[0].id == id)
        #expect(store.missingSessions[0].name == "Ghost")
    }

    @Test func initPartitionsReachableAndMissingSessions() throws {
        defer { cleanup() }
        // Reachable session
        let reachableID = UUID()
        let reachableSession = Session(
            id: reachableID, name: "Alive",
            workingDirectory: testWorkingDir.path,
            workflowName: "W", state: .idle,
            currentPhaseIndex: 0, currentStepIndex: 0, completedStepIDs: []
        )
        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: testWorkingDir, sessionID: reachableID)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try JSONEncoder().encode(reachableSession).write(
            to: SessionDirectoryLayout.stateFileURL(workingDirectory: testWorkingDir, sessionID: reachableID))
        try SessionRegistry(fileURL: registryURL).add(
            SessionRegistryEntry(id: reachableID, name: "Alive",
                                 workingDirectory: testWorkingDir.path, workflowName: "W"))

        // Missing session
        let missingID = UUID()
        try SessionRegistry(fileURL: registryURL).add(
            SessionRegistryEntry(id: missingID, name: "Ghost",
                                 workingDirectory: "/nonexistent-\(UUID().uuidString)", workflowName: "W"))

        let store = makeStore()
        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].id == reachableID)
        #expect(store.missingSessions.count == 1)
        #expect(store.missingSessions[0].id == missingID)
    }

    @Test func deleteMissingSessionRemovesFromMemoryAndRegistry() throws {
        defer { cleanup() }
        let id = UUID()
        let fakeWorkDir = "/nonexistent-path-\(UUID().uuidString)"
        try SessionRegistry(fileURL: registryURL).add(
            SessionRegistryEntry(id: id, name: "Ghost",
                                 workingDirectory: fakeWorkDir, workflowName: "W"))

        let store = makeStore()
        #expect(store.missingSessions.count == 1)

        store.deleteMissingSession(id: id)

        #expect(store.missingSessions.isEmpty)

        // Confirm removed from registry on disk
        let entries = try SessionRegistry(fileURL: registryURL).load()
        #expect(entries.isEmpty)
    }

    // MARK: - Relocate Missing Session

    @Test func relocateMissingSessionMovesToSessions() throws {
        defer { cleanup() }
        let id = UUID()
        let fakeWorkDir = "/nonexistent-path-\(UUID().uuidString)"
        try SessionRegistry(fileURL: registryURL).add(
            SessionRegistryEntry(id: id, name: "Relocated",
                                 workingDirectory: fakeWorkDir, workflowName: "W"))

        // Build the real session directory at the test working dir
        let session = Session(
            id: id, name: "Relocated",
            workingDirectory: testWorkingDir.path,
            workflowName: "W", state: .idle,
            currentPhaseIndex: 0, currentStepIndex: 0, completedStepIDs: []
        )
        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: testWorkingDir, sessionID: id)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(
            to: SessionDirectoryLayout.stateFileURL(workingDirectory: testWorkingDir, sessionID: id))

        let store = makeStore()
        #expect(store.missingSessions.count == 1)
        #expect(store.sessions.isEmpty)

        try store.relocateMissingSession(id: id, to: testWorkingDir.path)

        #expect(store.missingSessions.isEmpty)
        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].id == id)

        // Registry must reflect the new working directory
        let entries = try SessionRegistry(fileURL: registryURL).load()
        let entry = try #require(entries.first(where: { $0.id == id }))
        #expect(entry.workingDirectory == testWorkingDir.path)
    }

    @Test func relocateMissingSessionThrowsWhenSessionDirectoryAbsent() throws {
        defer { cleanup() }
        let id = UUID()
        let fakeWorkDir = "/nonexistent-path-\(UUID().uuidString)"
        try SessionRegistry(fileURL: registryURL).add(
            SessionRegistryEntry(id: id, name: "Ghost",
                                 workingDirectory: fakeWorkDir, workflowName: "W"))

        let store = makeStore()
        #expect(store.missingSessions.count == 1)

        // Provide a valid directory path that does NOT contain .aw-cache/{id}/
        let invalidTarget = testWorkingDir.path
        #expect(throws: SessionStoreRelocateError.sessionDirectoryNotFound) {
            try store.relocateMissingSession(id: id, to: invalidTarget)
        }

        // missingSessions and registry must remain unchanged
        #expect(store.missingSessions.count == 1)
        let entries = try SessionRegistry(fileURL: registryURL).load()
        let entry = try #require(entries.first(where: { $0.id == id }))
        #expect(entry.workingDirectory == fakeWorkDir)
    }

    @Test func deleteMissingSessionDoesNotTouchFileSystem() throws {
        defer { cleanup() }
        let id = UUID()
        // Point at a real directory to ensure we don't try to delete it
        try SessionRegistry(fileURL: registryURL).add(
            SessionRegistryEntry(id: id, name: "PointsAtReal",
                                 workingDirectory: testWorkingDir.path, workflowName: "W"))

        // Force it into missingSessions by using a fake reachability that always says missing
        let alwaysMissing = SessionReachability(isDirectory: { _ in false })
        let store = SessionStore(registryURL: registryURL, reachability: alwaysMissing)
        #expect(store.missingSessions.count == 1)

        store.deleteMissingSession(id: id)

        // The working directory itself must still exist (nothing deleted on disk)
        #expect(FileManager.default.fileExists(atPath: testWorkingDir.path))
        #expect(store.missingSessions.isEmpty)
    }
}
