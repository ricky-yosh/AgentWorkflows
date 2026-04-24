import Foundation
import Testing
@testable import AgentWorkflows

@Suite("SkillInstallExecutor")
struct SkillInstallExecutorTests {

    private func makeTempDir(label: String = "") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-executor-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeFile(content: String, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.data(using: .utf8)!.write(to: url)
    }

    @Test func mixedPlanProducesExpectedOnDiskState() throws {
        let sourceDir = try makeTempDir(label: "src")
        let destDir = try makeTempDir(label: "dst")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destDir)
        }

        let fm = FileManager.default

        // Source files for install and update ops
        let installSource = sourceDir.appendingPathComponent("ralph/SKILL.md")
        try writeFile(content: "ralph content", at: installSource)

        let updateSource = sourceDir.appendingPathComponent("grill-me/SKILL.md")
        try writeFile(content: "grill-me updated", at: updateSource)

        // Pre-populate destDir: grill-me (to be updated), qa (to be removed), prd-to-tasks (untouched)
        try writeFile(content: "old grill-me", at: destDir.appendingPathComponent("grill-me/SKILL.md"))
        try writeFile(content: "qa content", at: destDir.appendingPathComponent("qa/SKILL.md"))
        try writeFile(content: "custom prd-to-tasks", at: destDir.appendingPathComponent("prd-to-tasks/SKILL.md"))

        let plan = SkillInstaller.Plan(ops: [
            .install(name: "ralph", sourceURL: installSource),
            .update(name: "grill-me", sourceURL: updateSource, requiresConsent: false),
            .remove(name: "qa"),
        ], blocked: [])

        let results = SkillInstallExecutor.execute(plan: plan, skillsDirectory: destDir)

        // All three ops succeed
        #expect(results.count == 3)
        #expect(results[0] == SkillInstallExecutor.OpResult(skillName: "ralph", outcome: .succeeded))
        #expect(results[1] == SkillInstallExecutor.OpResult(skillName: "grill-me", outcome: .succeeded))
        #expect(results[2] == SkillInstallExecutor.OpResult(skillName: "qa", outcome: .succeeded))

        // ralph was installed
        let ralphFile = destDir.appendingPathComponent("ralph/SKILL.md")
        #expect(fm.fileExists(atPath: ralphFile.path))
        #expect(try String(contentsOf: ralphFile, encoding: .utf8) == "ralph content")

        // grill-me was updated
        let grillMeFile = destDir.appendingPathComponent("grill-me/SKILL.md")
        #expect(fm.fileExists(atPath: grillMeFile.path))
        #expect(try String(contentsOf: grillMeFile, encoding: .utf8) == "grill-me updated")

        // qa was removed
        #expect(!fm.fileExists(atPath: destDir.appendingPathComponent("qa").path))

        // prd-to-tasks was not in the plan and remains untouched
        let prdFile = destDir.appendingPathComponent("prd-to-tasks/SKILL.md")
        #expect(fm.fileExists(atPath: prdFile.path))
        #expect(try String(contentsOf: prdFile, encoding: .utf8) == "custom prd-to-tasks")
    }

    @Test func failedOpReportsErrorAndDoesNotAbortRemainingOps() throws {
        let sourceDir = try makeTempDir(label: "src")
        let destDir = try makeTempDir(label: "dst")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destDir)
        }

        let ralphSource = sourceDir.appendingPathComponent("ralph/SKILL.md")
        try writeFile(content: "ralph content", at: ralphSource)

        // Remove of a non-existent skill directory fails
        let plan = SkillInstaller.Plan(ops: [
            .remove(name: "nonexistent"),
            .install(name: "ralph", sourceURL: ralphSource),
        ], blocked: [])

        let results = SkillInstallExecutor.execute(plan: plan, skillsDirectory: destDir)

        #expect(results.count == 2)
        #expect(results[0].skillName == "nonexistent")
        let firstFailed: Bool
        if case .failed = results[0].outcome { firstFailed = true } else { firstFailed = false }
        #expect(firstFailed, "Expected failed outcome for remove of nonexistent skill")

        // Second op still ran and succeeded despite the prior failure
        #expect(results[1] == SkillInstallExecutor.OpResult(skillName: "ralph", outcome: .succeeded))
        #expect(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("ralph/SKILL.md").path))
    }

    @Test func installCreatesSkillDirectoryWhenAbsent() throws {
        let sourceDir = try makeTempDir(label: "src")
        let destDir = try makeTempDir(label: "dst")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destDir)
        }

        let source = sourceDir.appendingPathComponent("qa/SKILL.md")
        try writeFile(content: "qa skill", at: source)

        let plan = SkillInstaller.Plan(ops: [
            .install(name: "qa", sourceURL: source),
        ], blocked: [])

        let results = SkillInstallExecutor.execute(plan: plan, skillsDirectory: destDir)

        #expect(results == [SkillInstallExecutor.OpResult(skillName: "qa", outcome: .succeeded)])

        let destFile = destDir.appendingPathComponent("qa/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: destFile.path))
        #expect(try String(contentsOf: destFile, encoding: .utf8) == "qa skill")
    }
}
