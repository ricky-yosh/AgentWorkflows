import Foundation
import Testing
@testable import AgentWorkflows

@Suite("MigrationCleaner")
struct MigrationCleanerTests {

    private func makeTempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-cleaner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "migration-cleaner-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.data(using: .utf8)!.write(to: url)
    }

    @Test func firstRunWipesSessionsWorkflowsBlocksAndStaleKeys() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let config = root.appendingPathComponent(".config/AW", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        // Stale Session on disk — a directory with a state.json inside.
        let staleSessionDir = sessions.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try write(#"{"id":"old"}"#, to: staleSessionDir.appendingPathComponent("state.json"))

        // Stale workflows/ and blocks/ trees under ~/.config/AW.
        try write("# old workflow", to: config.appendingPathComponent("workflows/MyFlow/workflow.yaml"))
        try write("{}", to: config.appendingPathComponent("blocks/my-block.json"))

        // Stale UserDefaults keys plus a key that must survive the sweep.
        let defaults = makeDefaults()
        defaults.set("anthropic", forKey: "digestProvider")
        defaults.set("hello", forKey: "digestPromptTemplate")
        defaults.set("sk-xxx", forKey: "claudeAPIKey")
        defaults.set("cli/zsh", forKey: "defaultAgent")

        MigrationCleaner.runIfNeeded(
            sessionsDirectory: sessions,
            configDirectory: config,
            defaults: defaults
        )

        // Sessions directory itself survives; its contents are gone.
        #expect(FileManager.default.fileExists(atPath: sessions.path))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: sessions.path)
        #expect(remaining.isEmpty)

        // workflows/ and blocks/ subtrees are gone.
        #expect(FileManager.default.fileExists(atPath: config.appendingPathComponent("workflows").path) == false)
        #expect(FileManager.default.fileExists(atPath: config.appendingPathComponent("blocks").path) == false)

        // Stale keys cleared; untouched key preserved.
        #expect(defaults.string(forKey: "digestProvider") == nil)
        #expect(defaults.string(forKey: "digestPromptTemplate") == nil)
        #expect(defaults.string(forKey: "claudeAPIKey") == nil)
        #expect(defaults.string(forKey: "defaultAgent") == "cli/zsh")

        // Completion flag set.
        #expect(defaults.bool(forKey: MigrationCleaner.completionFlagKey) == true)
    }

    @Test func secondRunIsNoOp() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let config = root.appendingPathComponent(".config/AW", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let defaults = makeDefaults()
        MigrationCleaner.runIfNeeded(
            sessionsDirectory: sessions,
            configDirectory: config,
            defaults: defaults
        )
        #expect(defaults.bool(forKey: MigrationCleaner.completionFlagKey) == true)

        // Simulate a post-migration Session being created in place, and a
        // user writing a new stale-named UserDefaults key after the flag
        // was set. Neither should be touched by a second runIfNeeded().
        let freshSession = sessions.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try write(#"{"id":"new"}"#, to: freshSession.appendingPathComponent("state.json"))
        defaults.set("should-survive", forKey: "digestProvider")

        MigrationCleaner.runIfNeeded(
            sessionsDirectory: sessions,
            configDirectory: config,
            defaults: defaults
        )

        #expect(FileManager.default.fileExists(atPath: freshSession.appendingPathComponent("state.json").path))
        #expect(defaults.string(forKey: "digestProvider") == "should-survive")
    }

    @Test func purgeStaleSignalFilesRemovesStepCompleteFiles() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryURL = root.appendingPathComponent("sessions.json")
        let workingDir = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDir, withIntermediateDirectories: true)

        let idA = UUID()
        let idB = UUID()
        let entryA = SessionRegistryEntry(id: idA, name: "A", workingDirectory: workingDir.path, workflowName: "ralph")
        let entryB = SessionRegistryEntry(id: idB, name: "B", workingDirectory: workingDir.path, workflowName: "ralph")

        let registry = SessionRegistry(fileURL: registryURL)
        try registry.add(entryA)
        try registry.add(entryB)

        // Create each session directory and plant a stale signal file plus a
        // state.json that must survive the sweep.
        let sessionDirA = SessionDirectoryLayout.sessionDirectory(workingDirectory: workingDir, sessionID: idA)
        let sessionDirB = SessionDirectoryLayout.sessionDirectory(workingDirectory: workingDir, sessionID: idB)
        try FileManager.default.createDirectory(at: sessionDirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDirB, withIntermediateDirectories: true)

        let signalA = SessionDirectoryLayout.signalFileURL(workingDirectory: workingDir, sessionID: idA)
        let signalB = SessionDirectoryLayout.signalFileURL(workingDirectory: workingDir, sessionID: idB)
        let stateA = SessionDirectoryLayout.stateFileURL(workingDirectory: workingDir, sessionID: idA)

        try write("", to: signalA)
        try write("", to: signalB)
        try write("{}", to: stateA)

        MigrationCleaner.purgeStaleSignalFiles(registry: registry, reachability: .live)

        #expect(!FileManager.default.fileExists(atPath: signalA.path), "stale signal file for session A should be purged")
        #expect(!FileManager.default.fileExists(atPath: signalB.path), "stale signal file for session B should be purged")
        #expect(FileManager.default.fileExists(atPath: stateA.path), "state.json must survive the sweep")
    }

    @Test func purgeStaleSignalFilesLeavesAbsentSignalFileAlone() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryURL = root.appendingPathComponent("sessions.json")
        let workingDir = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDir, withIntermediateDirectories: true)

        let id = UUID()
        let entry = SessionRegistryEntry(id: id, name: "S", workingDirectory: workingDir.path, workflowName: "ralph")
        let registry = SessionRegistry(fileURL: registryURL)
        try registry.add(entry)

        let sessionDir = SessionDirectoryLayout.sessionDirectory(workingDirectory: workingDir, sessionID: id)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let stateFile = SessionDirectoryLayout.stateFileURL(workingDirectory: workingDir, sessionID: id)
        try write("{}", to: stateFile)

        // No signal file planted — sweep should not crash and state.json survives.
        MigrationCleaner.purgeStaleSignalFiles(registry: registry, reachability: .live)

        #expect(FileManager.default.fileExists(atPath: stateFile.path), "state.json must survive when no signal file is present")
    }

    @Test func purgeStaleSignalFilesIgnoresMissingSessions() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryURL = root.appendingPathComponent("sessions.json")
        // Working directory that does not exist — entry is unreachable.
        let ghostDir = root.appendingPathComponent("ghost-repo", isDirectory: true)

        let id = UUID()
        let entry = SessionRegistryEntry(id: id, name: "Ghost", workingDirectory: ghostDir.path, workflowName: "ralph")
        let registry = SessionRegistry(fileURL: registryURL)
        try registry.add(entry)

        // Should complete without error even though working directory is absent.
        MigrationCleaner.purgeStaleSignalFiles(registry: registry, reachability: .live)
    }

    @Test func missingDirectoriesAreHandledSilently() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("never-created-sessions", isDirectory: true)
        let config = root.appendingPathComponent("never-created-config", isDirectory: true)

        let defaults = makeDefaults()
        MigrationCleaner.runIfNeeded(
            sessionsDirectory: sessions,
            configDirectory: config,
            defaults: defaults
        )

        #expect(defaults.bool(forKey: MigrationCleaner.completionFlagKey) == true)
    }
}
