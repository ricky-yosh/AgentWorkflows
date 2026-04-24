import Foundation
import Testing
@testable import AgentWorkflows

@Suite("SkillInstaller")
struct SkillInstallerTests {

    private let fakeURL = URL(fileURLWithPath: "/fake/skills")

    private func skill(_ name: String, _ state: SkillClassifier.State) -> SkillInstaller.SkillInput {
        SkillInstaller.SkillInput(
            name: name,
            classification: state,
            sourceURL: fakeURL.appendingPathComponent("\(name)/SKILL.md")
        )
    }

    // MARK: - firstRun

    @Test func firstRunAllMissingProducesSixInstallOps() {
        let skills = PresenceChecker.requiredSkills.map { skill($0, .missing) }
        let plan = SkillInstaller.plan(skills: skills, intent: .firstRun)
        #expect(plan.ops.count == 6)
        #expect(plan.blocked.isEmpty)
        for op in plan.ops {
            if case .install = op { } else {
                Issue.record("Expected .install op, got \(op)")
            }
        }
    }

    @Test func firstRunMixedMissingAndCleanInstallsOnlyMissing() {
        let skills = [
            skill("ralph", .missing),
            skill("grill-me", .clean),
            skill("ubiquitous-language", .missing),
            skill("to-prd", .clean),
            skill("prd-to-tasks", .missing),
            skill("qa", .clean),
        ]
        let plan = SkillInstaller.plan(skills: skills, intent: .firstRun)
        #expect(plan.ops.count == 3)
        #expect(plan.blocked.isEmpty)
        let installedNames = plan.ops.compactMap { op -> String? in
            if case .install(let name, _) = op { return name }
            return nil
        }
        #expect(Set(installedNames) == ["ralph", "ubiquitous-language", "prd-to-tasks"])
    }

    @Test func firstRunSkipsModifiedAndStale() {
        let skills = [
            skill("ralph", .modified),
            skill("grill-me", .stale),
            skill("ubiquitous-language", .clean),
        ]
        let plan = SkillInstaller.plan(skills: skills, intent: .firstRun)
        #expect(plan.ops.isEmpty)
        #expect(plan.blocked.isEmpty)
    }

    // MARK: - updateAllClean

    @Test func updateAllCleanOmitsModified() {
        let skills = [
            skill("ralph", .clean),
            skill("grill-me", .stale),
            skill("ubiquitous-language", .modified),
            skill("to-prd", .missing),
        ]
        let plan = SkillInstaller.plan(skills: skills, intent: .updateAllClean)
        #expect(plan.ops.count == 2)
        #expect(plan.blocked.isEmpty)
        let updatedNames = plan.ops.compactMap { op -> String? in
            if case .update(let name, _, _) = op { return name }
            return nil
        }
        #expect(Set(updatedNames) == ["ralph", "grill-me"])
    }

    @Test func updateAllCleanSkipsMissing() {
        let skills = [skill("ralph", .missing)]
        let plan = SkillInstaller.plan(skills: skills, intent: .updateAllClean)
        #expect(plan.ops.isEmpty)
        #expect(plan.blocked.isEmpty)
    }

    @Test func updateAllCleanProducesNoConsentOps() {
        let skills = [skill("ralph", .stale), skill("grill-me", .clean)]
        let plan = SkillInstaller.plan(skills: skills, intent: .updateAllClean)
        for op in plan.ops {
            if case .update(_, _, let requiresConsent) = op {
                #expect(!requiresConsent)
            }
        }
    }

    // MARK: - updateAll

    @Test func updateAllMarksModifiedAsRequiresConsent() {
        let skills = [
            skill("ralph", .clean),
            skill("grill-me", .modified),
            skill("ubiquitous-language", .stale),
        ]
        let plan = SkillInstaller.plan(skills: skills, intent: .updateAll)
        #expect(plan.ops.count == 3)
        #expect(plan.blocked.isEmpty)
        let consentMap: [String: Bool] = plan.ops.reduce(into: [:]) { dict, op in
            if case .update(let name, _, let consent) = op {
                dict[name] = consent
            }
        }
        #expect(consentMap["ralph"] == false)
        #expect(consentMap["grill-me"] == true)
        #expect(consentMap["ubiquitous-language"] == false)
    }

    @Test func updateAllSkipsMissing() {
        let skills = [skill("ralph", .missing)]
        let plan = SkillInstaller.plan(skills: skills, intent: .updateAll)
        #expect(plan.ops.isEmpty)
        #expect(plan.blocked.isEmpty)
    }

    // MARK: - removeAllUnmodified

    @Test func removeAllUnmodifiedBlocksModifiedWithReason() {
        let skills = [
            skill("ralph", .clean),
            skill("grill-me", .stale),
            skill("ubiquitous-language", .modified),
        ]
        let plan = SkillInstaller.plan(skills: skills, intent: .removeAllUnmodified)
        let removedNames = plan.ops.compactMap { op -> String? in
            if case .remove(let name) = op { return name }
            return nil
        }
        #expect(Set(removedNames) == ["ralph", "grill-me"])
        #expect(plan.blocked.count == 1)
        #expect(plan.blocked[0].skillName == "ubiquitous-language")
        #expect(!plan.blocked[0].reason.isEmpty)
    }

    @Test func removeAllUnmodifiedSkipsMissing() {
        let skills = [skill("ralph", .missing)]
        let plan = SkillInstaller.plan(skills: skills, intent: .removeAllUnmodified)
        #expect(plan.ops.isEmpty)
        #expect(plan.blocked.isEmpty)
    }

    // MARK: - updateSpecific

    @Test func updateSpecificCleanProducesUpdateWithoutConsent() {
        let skills = [skill("ralph", .clean)]
        let plan = SkillInstaller.plan(skills: skills, intent: .updateSpecific(name: "ralph"))
        #expect(plan.ops == [.update(name: "ralph", sourceURL: fakeURL.appendingPathComponent("ralph/SKILL.md"), requiresConsent: false)])
        #expect(plan.blocked.isEmpty)
    }

    @Test func updateSpecificModifiedRequiresConsent() {
        let skills = [skill("ralph", .modified)]
        let plan = SkillInstaller.plan(skills: skills, intent: .updateSpecific(name: "ralph"))
        #expect(plan.ops == [.update(name: "ralph", sourceURL: fakeURL.appendingPathComponent("ralph/SKILL.md"), requiresConsent: true)])
        #expect(plan.blocked.isEmpty)
    }

    @Test func updateSpecificMissingProducesNoOps() {
        let skills = [skill("ralph", .missing)]
        let plan = SkillInstaller.plan(skills: skills, intent: .updateSpecific(name: "ralph"))
        #expect(plan.ops.isEmpty)
        #expect(plan.blocked.isEmpty)
    }

    @Test func updateSpecificUnknownNameProducesNoOps() {
        let skills = [skill("ralph", .clean)]
        let plan = SkillInstaller.plan(skills: skills, intent: .updateSpecific(name: "nonexistent"))
        #expect(plan.ops.isEmpty)
        #expect(plan.blocked.isEmpty)
    }

    // MARK: - removeSpecific

    @Test func removeSpecificCleanProducesRemoveOp() {
        let skills = [skill("ralph", .clean)]
        let plan = SkillInstaller.plan(skills: skills, intent: .removeSpecific(name: "ralph"))
        #expect(plan.ops == [.remove(name: "ralph")])
        #expect(plan.blocked.isEmpty)
    }

    @Test func removeSpecificModifiedGoesToBlockedList() {
        let skills = [skill("ralph", .modified)]
        let plan = SkillInstaller.plan(skills: skills, intent: .removeSpecific(name: "ralph"))
        #expect(plan.ops.isEmpty)
        #expect(plan.blocked.count == 1)
        #expect(plan.blocked[0].skillName == "ralph")
        #expect(!plan.blocked[0].reason.isEmpty)
    }

    @Test func removeSpecificStaleProducesRemoveOp() {
        let skills = [skill("ralph", .stale)]
        let plan = SkillInstaller.plan(skills: skills, intent: .removeSpecific(name: "ralph"))
        #expect(plan.ops == [.remove(name: "ralph")])
        #expect(plan.blocked.isEmpty)
    }

    @Test func removeSpecificMissingProducesNoOps() {
        let skills = [skill("ralph", .missing)]
        let plan = SkillInstaller.plan(skills: skills, intent: .removeSpecific(name: "ralph"))
        #expect(plan.ops.isEmpty)
        #expect(plan.blocked.isEmpty)
    }

    @Test func removeSpecificUnknownNameProducesNoOps() {
        let skills = [skill("ralph", .clean)]
        let plan = SkillInstaller.plan(skills: skills, intent: .removeSpecific(name: "nonexistent"))
        #expect(plan.ops.isEmpty)
        #expect(plan.blocked.isEmpty)
    }
}
