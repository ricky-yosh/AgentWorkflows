import Foundation
import Testing
@testable import AgentWorkflows

@Suite("SkillsPreferencesPane")
struct SkillsPreferencesPaneTests {

    // MARK: - isUpdateDisabled

    @Test func updateDisabledForMissing() {
        #expect(SkillsPreferencesPane.isUpdateDisabled(for: .missing))
    }

    @Test func updateEnabledForModified() {
        // Modified shows a consent sheet instead of being disabled.
        #expect(!SkillsPreferencesPane.isUpdateDisabled(for: .modified))
    }

    @Test func updateEnabledForClean() {
        #expect(!SkillsPreferencesPane.isUpdateDisabled(for: .clean))
    }

    @Test func updateEnabledForStale() {
        #expect(!SkillsPreferencesPane.isUpdateDisabled(for: .stale))
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
}
