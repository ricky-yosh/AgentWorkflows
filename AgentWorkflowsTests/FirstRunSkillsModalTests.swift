import Testing
@testable import AgentWorkflows

@Suite("FirstRunSkillsModal")
struct FirstRunSkillsModalTests {

    @Test func presentedWhenMissingSkillsAndFlagUnset() {
        #expect(FirstRunSkillsModal.shouldPresent(hasMissingSkills: true, dontShowAgain: false))
    }

    @Test func suppressedWhenDontShowAgainIsSet() {
        #expect(!FirstRunSkillsModal.shouldPresent(hasMissingSkills: true, dontShowAgain: true))
    }

    @Test func notPresentedWhenNoMissingSkills() {
        #expect(!FirstRunSkillsModal.shouldPresent(hasMissingSkills: false, dontShowAgain: false))
    }

    @Test func notPresentedWhenNoMissingSkillsAndFlagSet() {
        #expect(!FirstRunSkillsModal.shouldPresent(hasMissingSkills: false, dontShowAgain: true))
    }
}
