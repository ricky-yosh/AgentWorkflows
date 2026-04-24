import Foundation
import Observation

enum SessionStoreRelocateError: Error {
    case sessionDirectoryNotFound
    case stateFileNotReadable
}

@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var missingSessions: [SessionRegistryEntry] = []
    @ObservationIgnored private let registry: SessionRegistry
    @ObservationIgnored private let reachability: SessionReachability
    @ObservationIgnored private let watcherFactory: () -> any StateFileWatcher
    @ObservationIgnored private var watchers: [UUID: any StateFileWatcher] = [:]

    init(
        registryURL: URL = SessionRegistry.defaultFileURL,
        reachability: SessionReachability = .live,
        watcherFactory: @escaping () -> any StateFileWatcher = { DispatchSourceStateFileWatcher() }
    ) {
        self.registry = SessionRegistry(fileURL: registryURL)
        self.reachability = reachability
        self.watcherFactory = watcherFactory
        let scanned = Self.scanSessions(registry: SessionRegistry(fileURL: registryURL),
                                        reachability: reachability)
        self.sessions = scanned.reachable
        self.missingSessions = scanned.missing
        demoteRunningSessions()
        for session in sessions {
            attachWatcher(for: session)
        }
    }

    func createSession(workingDirectory: String, workflowName: String) throws -> Session {
        let name = placeholderName(for: Date())
        let session = Session(
            id: UUID(),
            name: name,
            workingDirectory: workingDirectory,
            workflowName: workflowName,
            state: .idle,
            currentPhaseIndex: 0,
            currentStepIndex: 0,
            completedStepIDs: []
        )

        let workingDirURL = URL(fileURLWithPath: workingDirectory)
        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: workingDirURL,
            sessionID: session.id
        )
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let gitignoreURL = SessionDirectoryLayout.gitignoreURL(workingDirectory: workingDirURL)
        if !FileManager.default.fileExists(atPath: gitignoreURL.path) {
            try "*".write(to: gitignoreURL, atomically: true, encoding: .utf8)
        }

        try writeStateJSON(for: session)

        let entry = SessionRegistryEntry(
            id: session.id,
            name: name,
            workingDirectory: workingDirectory,
            workflowName: workflowName
        )
        try registry.add(entry)

        sessions.append(session)
        attachWatcher(for: session)
        return session
    }

    func saveSession(_ session: Session) throws {
        try writeStateJSON(for: session)

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
    }

    func deleteSession(_ session: Session) throws {
        detachWatcher(for: session.id)

        let workingDirURL = URL(fileURLWithPath: session.workingDirectory)
        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: workingDirURL,
            sessionID: session.id
        )
        if FileManager.default.fileExists(atPath: sessionDir.path) {
            try? FileManager.default.removeItem(at: sessionDir)
        }

        try? registry.remove(id: session.id)

        sessions.removeAll(where: { $0.id == session.id })
    }

    func deleteMissingSession(id: UUID) {
        try? registry.remove(id: id)
        missingSessions.removeAll(where: { $0.id == id })
    }

    func relocateMissingSession(id: UUID, to newWorkingDirectory: String) throws {
        let newWorkingDirURL = URL(fileURLWithPath: newWorkingDirectory)
        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: newWorkingDirURL,
            sessionID: id
        )

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessionDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw SessionStoreRelocateError.sessionDirectoryNotFound
        }

        let stateFile = SessionDirectoryLayout.stateFileURL(workingDirectory: newWorkingDirURL, sessionID: id)
        guard let data = try? Data(contentsOf: stateFile),
              let session = try? JSONDecoder().decode(Session.self, from: data) else {
            throw SessionStoreRelocateError.stateFileNotReadable
        }

        try registry.relocate(id: id, to: newWorkingDirectory)
        missingSessions.removeAll(where: { $0.id == id })
        sessions.append(session)
        attachWatcher(for: session)
    }

    // MARK: - Paths

    func sessionDirectoryURL(for session: Session) -> URL {
        SessionDirectoryLayout.sessionDirectory(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: session.id
        )
    }

    // MARK: - Workflow Loading

    func loadWorkflow(for session: Session) -> Workflow? {
        Workflow.ralph
    }

    // MARK: - Braindump

    func writeBraindump(sessionID: UUID, text: String) throws {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: sessionID
        )
        let braindumpFile = sessionDir.appendingPathComponent("braindump.md")
        guard !FileManager.default.fileExists(atPath: braindumpFile.path) else { return }
        try Data(text.utf8).write(to: braindumpFile)
    }

    // MARK: - Rename

    func rename(sessionID: UUID, to newName: String, manual: Bool) throws {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        if !manual && sessions[index].manuallyTitled { return }
        sessions[index].name = newName
        if manual { sessions[index].manuallyTitled = true }
        try writeStateJSON(for: sessions[index])
        try? registry.rename(id: sessionID, to: newName)
    }

    // MARK: - State Transitions

    func transitionSession(_ id: UUID, to newState: SessionState) throws {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        try sessions[index].transition(to: newState)
        try writeStateJSON(for: sessions[index])
    }

    func updateSessionProgress(_ id: UUID, phaseIndex: Int, stepIndex: Int, completedStepIDs: [String]) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].currentPhaseIndex = phaseIndex
        sessions[index].currentStepIndex = stepIndex
        sessions[index].completedStepIDs = completedStepIDs
        try? writeStateJSON(for: sessions[index])
    }

    // MARK: - Private

    private func demoteRunningSessions() {
        for i in sessions.indices where sessions[i].state == .running {
            sessions[i].state = .paused
            try? writeStateJSON(for: sessions[i])
        }
    }

    private func writeStateJSON(for session: Session) throws {
        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: session.id
        )
        let data = try JSONEncoder().encode(session)
        try data.write(to: stateFile)
    }

    private static func scanSessions(
        registry: SessionRegistry,
        reachability: SessionReachability
    ) -> (reachable: [Session], missing: [SessionRegistryEntry]) {
        guard let entries = try? registry.load() else { return ([], []) }
        var reachable: [Session] = []
        var missing: [SessionRegistryEntry] = []
        for entry in entries {
            guard reachability.classify(entry: entry) == .reachable else {
                missing.append(entry)
                continue
            }
            let workingDir = URL(fileURLWithPath: entry.workingDirectory)
            let stateFile = SessionDirectoryLayout.stateFileURL(
                workingDirectory: workingDir,
                sessionID: entry.id
            )
            guard let data = try? Data(contentsOf: stateFile),
                  let session = try? JSONDecoder().decode(Session.self, from: data) else {
                continue
            }
            reachable.append(session)
        }
        return (reachable, missing)
    }

    private func attachWatcher(for session: Session) {
        let watcher = watcherFactory()
        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: session.id
        )
        watcher.onChange = { [weak self] in self?.refreshSession(id: session.id) }
        watcher.start(watching: stateFile)
        watchers[session.id] = watcher
    }

    private func detachWatcher(for id: UUID) {
        watchers[id]?.stop()
        watchers[id] = nil
    }

    private func refreshSession(id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        let stateFile = SessionDirectoryLayout.stateFileURL(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: id
        )
        guard let data = try? Data(contentsOf: stateFile),
              let updated = try? JSONDecoder().decode(Session.self, from: data),
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index] = updated
    }
}
