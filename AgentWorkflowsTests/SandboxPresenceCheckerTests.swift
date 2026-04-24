import Foundation
import Testing
@testable import AgentWorkflows

@Suite("SandboxPresenceChecker")
struct SandboxPresenceCheckerTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-checker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ contents: String, to url: URL) throws {
        try contents.data(using: .utf8)!.write(to: url)
    }

    @Test func globalOnlyReportsEnabled() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let global = dir.appendingPathComponent("settings.json")
        try write(#"{"sandbox":{"enabled":true}}"#, to: global)

        let result = SandboxPresenceChecker.check(
            globalSettingsPath: global,
            projectSettingsPath: nil
        )

        #expect(result.sandboxEnabled == true)
        #expect(result.source == global.path)
    }

    @Test func projectOnlyReportsEnabled() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = dir.appendingPathComponent("settings.local.json")
        try write(#"{"sandbox":{"enabled":true}}"#, to: project)

        let result = SandboxPresenceChecker.check(
            globalSettingsPath: nil,
            projectSettingsPath: project
        )

        #expect(result.sandboxEnabled == true)
        #expect(result.source == project.path)
    }

    @Test func bothEnabledReportsProjectAsSource() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let global = dir.appendingPathComponent("settings.json")
        let project = dir.appendingPathComponent("settings.local.json")
        try write(#"{"sandbox":{"enabled":true}}"#, to: global)
        try write(#"{"sandbox":{"enabled":true}}"#, to: project)

        let result = SandboxPresenceChecker.check(
            globalSettingsPath: global,
            projectSettingsPath: project
        )

        #expect(result.sandboxEnabled == true)
        #expect(result.source == project.path)
    }

    @Test func neitherEnabledReportsDisabled() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let global = dir.appendingPathComponent("settings.json")
        let project = dir.appendingPathComponent("settings.local.json")
        try write(#"{"sandbox":{"enabled":false}}"#, to: global)
        try write(#"{"permissions":{"allow":[]}}"#, to: project)

        let result = SandboxPresenceChecker.check(
            globalSettingsPath: global,
            projectSettingsPath: project
        )

        #expect(result.sandboxEnabled == false)
        #expect(result.source == nil)
    }

    @Test func missingFilesReportDisabled() {
        let bogus = URL(fileURLWithPath: "/tmp/definitely-does-not-exist-\(UUID().uuidString).json")
        let result = SandboxPresenceChecker.check(
            globalSettingsPath: bogus,
            projectSettingsPath: nil
        )
        #expect(result.sandboxEnabled == false)
        #expect(result.source == nil)
    }

    @Test func malformedJsonDegradesToDisabled() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let global = dir.appendingPathComponent("settings.json")
        try write("{not valid json", to: global)

        let result = SandboxPresenceChecker.check(
            globalSettingsPath: global,
            projectSettingsPath: nil
        )

        #expect(result.sandboxEnabled == false)
        #expect(result.source == nil)
    }

    @Test func malformedProjectFallsThroughToGlobal() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let global = dir.appendingPathComponent("settings.json")
        let project = dir.appendingPathComponent("settings.local.json")
        try write(#"{"sandbox":{"enabled":true}}"#, to: global)
        try write("}}}not json", to: project)

        let result = SandboxPresenceChecker.check(
            globalSettingsPath: global,
            projectSettingsPath: project
        )

        #expect(result.sandboxEnabled == true)
        #expect(result.source == global.path)
    }

    @Test func writesNothingToSettingsFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let global = dir.appendingPathComponent("settings.json")
        let original = #"{"sandbox":{"enabled":false},"other":42}"#
        try write(original, to: global)
        let attrsBefore = try FileManager.default.attributesOfItem(atPath: global.path)
        let mtimeBefore = attrsBefore[.modificationDate] as? Date

        _ = SandboxPresenceChecker.check(globalSettingsPath: global, projectSettingsPath: nil)

        let after = try String(contentsOf: global, encoding: .utf8)
        #expect(after == original)
        let attrsAfter = try FileManager.default.attributesOfItem(atPath: global.path)
        let mtimeAfter = attrsAfter[.modificationDate] as? Date
        #expect(mtimeBefore == mtimeAfter)
    }
}
