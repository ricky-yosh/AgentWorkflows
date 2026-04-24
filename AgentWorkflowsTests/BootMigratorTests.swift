import Foundation
import Testing
@testable import AgentWorkflows

@Suite("BootMigrator")
struct BootMigratorTests {

    private func makeTempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("boot-migrator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "boot-migrator-tests-\(UUID().uuidString)"
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

    @Test func firstRunDeletesLegacySessionsDirectory() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let stateFile = sessions
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("state.json")
        try write(#"{"id":"legacy"}"#, to: stateFile)

        let defaults = makeDefaults()
        BootMigrator.runIfNeeded(legacySessionsDirectory: sessions, defaults: defaults)

        #expect(!FileManager.default.fileExists(atPath: sessions.path),
                "legacy sessions directory must be deleted on first run")
        #expect(defaults.bool(forKey: BootMigrator.completionFlagKey),
                "completion flag must be set after first run")
    }

    @Test func secondRunIsNoOp() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = root.appendingPathComponent("sessions", isDirectory: true)

        let defaults = makeDefaults()
        BootMigrator.runIfNeeded(legacySessionsDirectory: sessions, defaults: defaults)
        #expect(defaults.bool(forKey: BootMigrator.completionFlagKey))

        // Simulate a post-migration sessions directory being (re-)created.
        let stateFile = sessions
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("state.json")
        try write(#"{"id":"new"}"#, to: stateFile)

        BootMigrator.runIfNeeded(legacySessionsDirectory: sessions, defaults: defaults)

        #expect(FileManager.default.fileExists(atPath: stateFile.path),
                "post-migration contents must survive the second (no-op) run")
    }

    @Test func missingLegacyDirectorySetsFlag() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = root.appendingPathComponent("sessions-never-created", isDirectory: true)

        let defaults = makeDefaults()
        BootMigrator.runIfNeeded(legacySessionsDirectory: sessions, defaults: defaults)

        #expect(defaults.bool(forKey: BootMigrator.completionFlagKey),
                "flag must be set even when legacy directory does not exist")
    }
}
