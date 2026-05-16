import Foundation
import Testing
@testable import AgentWorkflows

@Suite("SkillsPreferencesPane")
struct SkillsPreferencesPaneTests {

    // MARK: - updateButtonLabel

    @Test func updateButtonLabelIsInstallForMissing() {
        #expect(SkillsPreferencesPane.updateButtonLabel(for: .missing) == "Install")
    }

    @Test func updateButtonLabelIsUpdateForModified() {
        #expect(SkillsPreferencesPane.updateButtonLabel(for: .modified) == "Update")
    }

    @Test func updateButtonLabelIsUpdateForClean() {
        #expect(SkillsPreferencesPane.updateButtonLabel(for: .clean) == "Update")
    }

    @Test func updateButtonLabelIsUpdateForStale() {
        #expect(SkillsPreferencesPane.updateButtonLabel(for: .stale) == "Update")
    }

    // MARK: - isRemoveDisabled

    @Test func removeDisabledForMissing() {
        #expect(SkillsPreferencesPane.isRemoveDisabled(for: .missing))
    }

    @Test func removeDisabledForModified() {
        #expect(SkillsPreferencesPane.isRemoveDisabled(for: .modified))
    }

    @Test func removeEnabledForClean() {
        #expect(!SkillsPreferencesPane.isRemoveDisabled(for: .clean))
    }

    @Test func removeEnabledForStale() {
        #expect(!SkillsPreferencesPane.isRemoveDisabled(for: .stale))
    }

    // MARK: - removeDisabledReason

    @Test func removeDisabledReasonPresentForModified() {
        let reason = SkillsPreferencesPane.removeDisabledReason(for: .modified)
        #expect(reason != nil)
    }

    @Test func removeDisabledReasonAbsentForClean() {
        #expect(SkillsPreferencesPane.removeDisabledReason(for: .clean) == nil)
    }

    @Test func removeDisabledReasonAbsentForStale() {
        #expect(SkillsPreferencesPane.removeDisabledReason(for: .stale) == nil)
    }

    @Test func removeDisabledReasonAbsentForMissing() {
        #expect(SkillsPreferencesPane.removeDisabledReason(for: .missing) == nil)
    }

    // MARK: - opsRequiringConsent

    @Test func opsRequiringConsentReturnsOnlyConsentUpdates() {
        let url = URL(fileURLWithPath: "/tmp/SKILL.md")
        let plan = SkillInstaller.Plan(
            ops: [
                .update(name: "foo", sourceURL: url, requiresConsent: true),
                .update(name: "bar", sourceURL: url, requiresConsent: false),
                .install(name: "baz", sourceURL: url),
            ],
            blocked: []
        )
        let consent = SkillsPreferencesPane.opsRequiringConsent(in: plan)
        #expect(consent.count == 1)
        guard case .update(let name, _, _) = consent[0] else {
            Issue.record("Expected an update op")
            return
        }
        #expect(name == "foo")
    }

    @Test func opsRequiringConsentEmptyWhenNoConsentNeeded() {
        let url = URL(fileURLWithPath: "/tmp/SKILL.md")
        let plan = SkillInstaller.Plan(
            ops: [
                .update(name: "bar", sourceURL: url, requiresConsent: false),
                .remove(name: "baz"),
            ],
            blocked: []
        )
        #expect(SkillsPreferencesPane.opsRequiringConsent(in: plan).isEmpty)
    }

    @Test func makeSectionsIncludesPiTargetWithAgentsSkillsDirectory() {
        let manifestByName = Dictionary(
            uniqueKeysWithValues: PresenceChecker.requiredSkills.map {
                ($0, SkillManifestEntry(name: $0, sha256: "hash-\($0)", priorSha256s: []))
            }
        )
        let bundledByName = Dictionary(
            uniqueKeysWithValues: PresenceChecker.requiredSkills.map {
                ($0, SkillBundleReader.BundledSkill(name: $0, fileURL: URL(fileURLWithPath: "/tmp/\($0)/SKILL.md")))
            }
        )

        let sections = SkillsPreferencesPane.makeSections(
            manifestByName: manifestByName,
            bundledByName: bundledByName
        )

        #expect(sections.count == SkillTarget.allCases.count)
        let piSection = sections.first(where: { $0.target == .pi })
        #expect(piSection != nil)
        #expect(piSection?.directory.path.hasSuffix(".agents/skills") == true)
        #expect(piSection?.rows.count == PresenceChecker.requiredSkills.count)
    }

    @Test func makeSectionsKeepsCliTargetsIndependent() {
        let manifestByName = Dictionary(
            uniqueKeysWithValues: PresenceChecker.requiredSkills.map {
                ($0, SkillManifestEntry(name: $0, sha256: "hash-\($0)", priorSha256s: []))
            }
        )
        let bundledByName = Dictionary(
            uniqueKeysWithValues: PresenceChecker.requiredSkills.map {
                ($0, SkillBundleReader.BundledSkill(name: $0, fileURL: URL(fileURLWithPath: "/tmp/\($0)/SKILL.md")))
            }
        )

        let sections = SkillsPreferencesPane.makeSections(
            manifestByName: manifestByName,
            bundledByName: bundledByName
        )

        let directories = Set(sections.map(\.directory.path))
        #expect(directories.count == SkillTarget.allCases.count)
        #expect(directories.contains(SkillTarget.claude.directory.path))
        #expect(directories.contains(SkillTarget.codex.directory.path))
        #expect(directories.contains(SkillTarget.pi.directory.path))
        #expect(directories.contains(SkillTarget.openCode.directory.path))
    }
}
