import Foundation
import Testing
@testable import AgentWorkflows

@Suite("PresenceBanner")
struct PresenceBannerTests {

    private let testDir = URL(fileURLWithPath: "/tmp/test-skills", isDirectory: true)

    private func report(missingSkills: Set<String> = []) -> PresenceChecker.Report {
        let missing = PresenceChecker.requiredSkills
            .filter { missingSkills.contains($0) }
            .map { PresenceChecker.MissingSkill(name: $0, directory: testDir) }
        return PresenceChecker.Report(missingSkillsByDirectory: missing)
    }

    @Test func hasMissingIsFalseWhenEverythingPresent() {
        let r = report()
        #expect(!PresenceBanner.hasMissing(r))
        #expect(PresenceBanner.missingRows(for: r).isEmpty)
    }

    @Test func missingSkillsProduceRowsInDeclaredOrder() {
        let r = report(missingSkills: ["qa", "ralph"])
        let rows = PresenceBanner.missingRows(for: r)
        #expect(PresenceBanner.hasMissing(r))
        #expect(rows.map { $0.id.hasPrefix("skill.ralph") }.contains(true))
        #expect(rows.map { $0.id.hasPrefix("skill.qa") }.contains(true))
        // ralph comes before qa in requiredSkills order
        let names = rows.compactMap { row -> String? in
            guard row.id.hasPrefix("skill.") else { return nil }
            return String(row.id.dropFirst("skill.".count).prefix(while: { $0 != "." }))
        }
        #expect(names == ["ralph", "qa"])
    }

    @Test func missingSingleSkillProducesOneInstallableRow() {
        let r = report(missingSkills: ["ralph"])
        let rows = PresenceBanner.missingRows(for: r)
        #expect(rows.count == 1)
        #expect(rows[0].id.hasPrefix("skill.ralph"))
        #expect(rows[0].isInstallable == true)
    }

    @Test func skillRowsAreInstallable() {
        let r = report(missingSkills: ["ralph"])
        let rows = PresenceBanner.missingRows(for: r)
        let skillRow = rows.first { $0.id.hasPrefix("skill.ralph") }
        #expect(skillRow?.isInstallable == true)
    }

    @Test func installInputsForMissingBuildsInputsForMissingSkillsOnly() {
        let r = report(missingSkills: ["ralph", "qa"])
        let bundledSkills = PresenceChecker.requiredSkills.map { name in
            SkillBundleReader.BundledSkill(
                name: name,
                fileURL: URL(fileURLWithPath: "/tmp/Skills/\(name)/SKILL.md")
            )
        }
        let inputs = PresenceBanner.installInputsForMissing(report: r, directory: testDir, bundledSkills: bundledSkills)
        #expect(inputs.count == 2)
        #expect(inputs.allSatisfy { $0.classification == .missing })
        #expect(Set(inputs.map(\.name)) == ["ralph", "qa"])
    }

    @Test func installInputsForMissingFiltersToSpecificDirectory() {
        let otherDir = URL(fileURLWithPath: "/tmp/other-skills", isDirectory: true)
        let mixed = PresenceChecker.Report(
            missingSkillsByDirectory: [
                PresenceChecker.MissingSkill(name: "ralph", directory: testDir),
                PresenceChecker.MissingSkill(name: "qa", directory: otherDir),
            ]
        )
        let bundledSkills = PresenceChecker.requiredSkills.map { name in
            SkillBundleReader.BundledSkill(
                name: name,
                fileURL: URL(fileURLWithPath: "/tmp/Skills/\(name)/SKILL.md")
            )
        }
        let inputs = PresenceBanner.installInputsForMissing(report: mixed, directory: testDir, bundledSkills: bundledSkills)
        #expect(inputs.count == 1)
        #expect(inputs.first?.name == "ralph")
    }
}
