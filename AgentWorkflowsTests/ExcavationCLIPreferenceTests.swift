import Testing
@testable import AgentWorkflows

@Suite("ExcavationCLIPreference")
struct ExcavationCLIPreferenceTests {

    @Test func sectionTitleMatchesPreferencesCopy() {
        #expect(ExcavationCLIPreference.sectionTitle == "Excavation CLI")
    }

    @Test func detailTextMentionsTheExcavationAgent() {
        #expect(ExcavationCLIPreference.detailText.contains("ExcavationAgent"))
    }
}
