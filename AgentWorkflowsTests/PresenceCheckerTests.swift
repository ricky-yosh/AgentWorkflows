import Foundation
import Testing
@testable import AgentWorkflows

@Suite("PresenceChecker")
struct PresenceCheckerTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("presence-checker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.data(using: .utf8)!.write(to: url)
    }

    private func installSkill(_ name: String, in skillsDir: URL) throws {
        let skillFile = skillsDir
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("SKILL.md")
        try write("# \(name)\n", to: skillFile)
    }

    @Test func requiredSkillsListIsExactlyTheSix() {
        #expect(PresenceChecker.requiredSkills == [
            "ralph", "grill-me", "ubiquitous-language",
            "to-prd", "prd-to-tasks", "qa",
        ])
    }

    @Test func allSkillsPresent() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let skills = root.appendingPathComponent("skills", isDirectory: true)
        for name in PresenceChecker.requiredSkills {
            try installSkill(name, in: skills)
        }
        let global = root.appendingPathComponent("settings.json")
        try write(#"{"sandbox":{"enabled":true}}"#, to: global)

        let report = PresenceChecker.check(
            skillsDirectories: [skills],
            globalSettingsPath: global,
            projectSettingsPath: nil
        )

        #expect(report.allSkillsPresent == true)
        #expect(report.missingSkills == [])
    }

    @Test func allSkillsAbsent() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let skills = root.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)

        let report = PresenceChecker.check(
            skillsDirectories: [skills],
            globalSettingsPath: nil,
            projectSettingsPath: nil
        )

        #expect(report.allSkillsPresent == false)
        #expect(report.missingSkills == PresenceChecker.requiredSkills)
    }

    @Test func mixedPresence() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let skills = root.appendingPathComponent("skills", isDirectory: true)
        try installSkill("ralph", in: skills)
        try installSkill("qa", in: skills)
        try installSkill("to-prd", in: skills)

        let report = PresenceChecker.check(
            skillsDirectories: [skills],
            globalSettingsPath: nil,
            projectSettingsPath: nil
        )

        #expect(!report.missingSkills.contains("ralph"))
        #expect(!report.missingSkills.contains("qa"))
        #expect(!report.missingSkills.contains("to-prd"))
        #expect(report.missingSkills.contains("grill-me"))
        #expect(report.missingSkills.contains("ubiquitous-language"))
        #expect(report.missingSkills.contains("prd-to-tasks"))
        #expect(report.missingSkills == ["grill-me", "ubiquitous-language", "prd-to-tasks"])
    }

    @Test func missingSkillsDirectoryDegradesToAllAbsent() {
        let bogus = URL(fileURLWithPath: "/tmp/definitely-does-not-exist-\(UUID().uuidString)")
        let report = PresenceChecker.check(
            skillsDirectories: [bogus],
            globalSettingsPath: nil,
            projectSettingsPath: nil
        )
        #expect(report.allSkillsPresent == false)
        #expect(report.missingSkills == PresenceChecker.requiredSkills)
    }

    @Test func skillDirectoryWithoutSkillMdIsAbsent() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let skills = root.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(
            at: skills.appendingPathComponent("ralph", isDirectory: true),
            withIntermediateDirectories: true
        )

        let report = PresenceChecker.check(
            skillsDirectories: [skills],
            globalSettingsPath: nil,
            projectSettingsPath: nil
        )

        #expect(report.missingSkills.contains("ralph"))
    }

    @Test func multipleDirectoriesReportsEachIndependently() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let claudeSkills = root.appendingPathComponent("claude-skills", isDirectory: true)
        let codexSkills = root.appendingPathComponent("codex-skills", isDirectory: true)
        for name in PresenceChecker.requiredSkills {
            try installSkill(name, in: claudeSkills)
        }
        // codex has none installed

        let report = PresenceChecker.check(
            skillsDirectories: [claudeSkills, codexSkills],
            globalSettingsPath: nil,
            projectSettingsPath: nil
        )

        // All 6 skills missing in codex dir
        let codexMissing = report.missingSkillsByDirectory.filter { $0.directory == codexSkills }
        #expect(codexMissing.count == PresenceChecker.requiredSkills.count)
        // None missing in claude dir
        let claudeMissing = report.missingSkillsByDirectory.filter { $0.directory == claudeSkills }
        #expect(claudeMissing.isEmpty)
        // Overall not all present
        #expect(!report.allSkillsPresent)
    }

    @Test func writesNothingToSkillsOrSettings() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let skills = root.appendingPathComponent("skills", isDirectory: true)
        try installSkill("ralph", in: skills)
        let skillFile = skills.appendingPathComponent("ralph/SKILL.md")
        let originalBody = try String(contentsOf: skillFile, encoding: .utf8)
        let mtimeBefore = try FileManager.default.attributesOfItem(atPath: skillFile.path)[.modificationDate] as? Date

        let global = root.appendingPathComponent("settings.json")
        let originalSettings = #"{"sandbox":{"enabled":false}}"#
        try write(originalSettings, to: global)
        let settingsMtimeBefore = try FileManager.default.attributesOfItem(atPath: global.path)[.modificationDate] as? Date

        _ = PresenceChecker.check(
            skillsDirectories: [skills],
            globalSettingsPath: global,
            projectSettingsPath: nil
        )

        #expect(try String(contentsOf: skillFile, encoding: .utf8) == originalBody)
        #expect(try String(contentsOf: global, encoding: .utf8) == originalSettings)
        let mtimeAfter = try FileManager.default.attributesOfItem(atPath: skillFile.path)[.modificationDate] as? Date
        let settingsMtimeAfter = try FileManager.default.attributesOfItem(atPath: global.path)[.modificationDate] as? Date
        #expect(mtimeBefore == mtimeAfter)
        #expect(settingsMtimeBefore == settingsMtimeAfter)
    }
}
