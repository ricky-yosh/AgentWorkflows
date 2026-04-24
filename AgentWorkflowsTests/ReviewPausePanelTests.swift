import Testing
import Foundation
@testable import AgentWorkflows

struct ReviewPausePanelTests {

    @Test func ralphWorkflowHasNoPauseSteps() {
        let allSteps = Workflow.ralph.phases.flatMap { $0.steps }
        #expect(allSteps.allSatisfy { $0.type != .pause })
    }

    @Test func unknownStepIDReturnsEmpty() {
        #expect(ReviewPausePanel.artifacts(for: "some-other-step").isEmpty)
        #expect(ReviewPausePanel.artifacts(for: "").isEmpty)
    }
}
