import Testing
@testable import AgentWorkflows
import Foundation

@Suite("SkillInstallResultSheet")
struct SkillInstallResultSheetTests {

    // MARK: - hasFailures

    @Test func hasFailuresReturnsTrueWhenOneResultFailed() {
        let results: [SkillInstallExecutor.OpResult] = [
            .init(skillName: "ralph", outcome: .succeeded),
            .init(skillName: "qa", outcome: .failed("Permission denied")),
        ]
        #expect(SkillInstallResultSheet.hasFailures(in: results))
    }

    @Test func hasFailuresReturnsFalseWhenAllSucceeded() {
        let results: [SkillInstallExecutor.OpResult] = [
            .init(skillName: "ralph", outcome: .succeeded),
            .init(skillName: "qa", outcome: .succeeded),
        ]
        #expect(!SkillInstallResultSheet.hasFailures(in: results))
    }

    @Test func hasFailuresReturnsFalseForEmptyResults() {
        #expect(!SkillInstallResultSheet.hasFailures(in: []))
    }

    // MARK: - shouldPresent

    @Test func shouldPresentReturnsTrueWhenResultsPresent() {
        let results = [SkillInstallExecutor.OpResult(skillName: "ralph", outcome: .succeeded)]
        #expect(SkillInstallResultSheet.shouldPresent(results: results, blocked: []))
    }

    @Test func shouldPresentReturnsTrueWhenBlockedPresent() {
        let blocked = [SkillInstaller.BlockedOp(skillName: "qa", reason: "Skill has been locally modified")]
        #expect(SkillInstallResultSheet.shouldPresent(results: [], blocked: blocked))
    }

    @Test func shouldPresentReturnsFalseWhenBothEmpty() {
        #expect(!SkillInstallResultSheet.shouldPresent(results: [], blocked: []))
    }
}
