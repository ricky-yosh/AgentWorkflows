import Foundation
import CryptoKit
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

        let updateSource = sourceDir.appendingPathComponent("grill-with-docs/SKILL.md")
        try writeFile(content: "grill-with-docs updated", at: updateSource)

        // Pre-populate destDir: grill-with-docs (to be updated), qa (to be removed), to-tasks (untouched)
        try writeFile(content: "old grill-with-docs", at: destDir.appendingPathComponent("grill-with-docs/SKILL.md"))
        try writeFile(content: "qa content", at: destDir.appendingPathComponent("qa/SKILL.md"))
        try writeFile(content: "custom to-tasks", at: destDir.appendingPathComponent("to-tasks/SKILL.md"))

        let plan = SkillInstaller.Plan(ops: [
            .install(name: "ralph", sourceURL: installSource),
            .update(name: "grill-with-docs", sourceURL: updateSource, requiresConsent: false),
            .remove(name: "qa"),
        ], blocked: [])

        let results = SkillInstallExecutor.execute(plan: plan, skillsDirectory: destDir, target: .claude)

        // All three ops succeed
        #expect(results.count == 3)
        #expect(results[0] == SkillInstallExecutor.OpResult(skillName: "ralph", outcome: .succeeded))
        #expect(results[1] == SkillInstallExecutor.OpResult(skillName: "grill-with-docs", outcome: .succeeded))
        #expect(results[2] == SkillInstallExecutor.OpResult(skillName: "qa", outcome: .succeeded))

        // ralph was installed
        let ralphFile = destDir.appendingPathComponent("ralph/SKILL.md")
        #expect(fm.fileExists(atPath: ralphFile.path))
        #expect(try String(contentsOf: ralphFile, encoding: .utf8) == "ralph content")

        // grill-with-docs was updated
        let grillWithDocsFile = destDir.appendingPathComponent("grill-with-docs/SKILL.md")
        #expect(fm.fileExists(atPath: grillWithDocsFile.path))
        #expect(try String(contentsOf: grillWithDocsFile, encoding: .utf8) == "grill-with-docs updated")

        // qa was removed
        #expect(!fm.fileExists(atPath: destDir.appendingPathComponent("qa").path))

        // to-tasks was not in the plan and remains untouched
        let tasksFile = destDir.appendingPathComponent("to-tasks/SKILL.md")
        #expect(fm.fileExists(atPath: tasksFile.path))
        #expect(try String(contentsOf: tasksFile, encoding: .utf8) == "custom to-tasks")
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

        let results = SkillInstallExecutor.execute(plan: plan, skillsDirectory: destDir, target: .claude)

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

        let results = SkillInstallExecutor.execute(plan: plan, skillsDirectory: destDir, target: .claude)

        #expect(results == [SkillInstallExecutor.OpResult(skillName: "qa", outcome: .succeeded)])

        let destFile = destDir.appendingPathComponent("qa/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: destFile.path))
        #expect(try String(contentsOf: destFile, encoding: .utf8) == "qa skill")
        let installedData = try Data(contentsOf: destFile)
        let installedHash = SHA256.hash(data: installedData).map { String(format: "%02x", $0) }.joined()
        #expect(SkillClassifier.classify(bytesOnDisk: installedData, currentHash: installedHash, priorHashes: []) == .clean)
    }

    @Test func installCanTargetPiSkillsDirectory() throws {
        let sourceDir = try makeTempDir(label: "src")
        let root = try makeTempDir(label: "pi-root")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: root)
        }

        let source = sourceDir.appendingPathComponent("ralph/SKILL.md")
        try writeFile(content: "ralph for pi", at: source)

        let piSkillsDirectory = root.appendingPathComponent(".agents/skills", isDirectory: true)
        let plan = SkillInstaller.Plan(ops: [
            .install(name: "ralph", sourceURL: source),
        ], blocked: [])

        let results = SkillInstallExecutor.execute(plan: plan, skillsDirectory: piSkillsDirectory, target: .pi)

        #expect(results == [SkillInstallExecutor.OpResult(skillName: "ralph", outcome: .succeeded)])
        let installed = piSkillsDirectory.appendingPathComponent("ralph/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: installed.path))
        #expect(try String(contentsOf: installed, encoding: .utf8) == "ralph for pi")
    }

    @Test func openCodeUsesFlatMarkdownFileForInstallUpdateAndRemove() throws {
        let sourceDir = try makeTempDir(label: "src")
        let commandsDir = try makeTempDir(label: "open-code")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: commandsDir)
        }

        let installSource = sourceDir.appendingPathComponent("ralph/SKILL.md")
        let updateSource = sourceDir.appendingPathComponent("qa/SKILL.md")
        try writeFile(content: "ralph v1", at: installSource)
        try writeFile(content: "qa v2", at: updateSource)
        try writeFile(content: "qa v1", at: commandsDir.appendingPathComponent("qa.md"))

        let plan = SkillInstaller.Plan(ops: [
            .install(name: "ralph", sourceURL: installSource),
            .update(name: "qa", sourceURL: updateSource, requiresConsent: false),
            .remove(name: "qa"),
        ], blocked: [])

        let results = SkillInstallExecutor.execute(plan: plan, skillsDirectory: commandsDir, target: .openCode)

        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.outcome == .succeeded })

        let installedFlat = commandsDir.appendingPathComponent("ralph.md")
        #expect(FileManager.default.fileExists(atPath: installedFlat.path))
        #expect(try String(contentsOf: installedFlat, encoding: .utf8) == "ralph v1")
        #expect(!FileManager.default.fileExists(atPath: commandsDir.appendingPathComponent("ralph/SKILL.md").path))
        #expect(!FileManager.default.fileExists(atPath: commandsDir.appendingPathComponent("qa.md").path))
    }
}
