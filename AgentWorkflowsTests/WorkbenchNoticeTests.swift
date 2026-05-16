import Foundation
import Testing
@testable import AgentWorkflows

@Suite("Workbench notices")
struct WorkbenchNoticeTests {

    @Test func warningPayloadProducesWarningNotice() {
        let model = WorkbenchModel(
            outskirts: [OutskirtsNode(name: "APIClient", file: "Sources/APIClient.swift")]
        )

        let notices = WorkbenchNoticeResolver.notices(
            for: model,
            warningPayload: "Dropped malformed outskirts entry"
        )

        #expect(notices == [.warning("Dropped malformed outskirts entry")])
    }

    @Test func emptyModelProducesEmptyExcavationNotice() {
        let notices = WorkbenchNoticeResolver.notices(
            for: WorkbenchModel(),
            warningPayload: nil
        )

        #expect(notices == [.emptyExcavation])
    }

    @Test func warningAndEmptyModelBothSurface() {
        let notices = WorkbenchNoticeResolver.notices(
            for: WorkbenchModel(),
            warningPayload: "Unsupported language: Foo"
        )

        #expect(notices.count == 2)
        #expect(notices.contains(.warning("Unsupported language: Foo")))
        #expect(notices.contains(.emptyExcavation))
    }
}
