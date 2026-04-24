import Testing
@testable import AgentWorkflows

@MainActor
struct SessionRunStatusTests {

    @Test("applyIteration stamps endDate on the last IterationRecord")
    func applyIterationStampsEndDate() async throws {
        let status = SessionRunStatus()
        status.beginIteration(number: 1, taskID: 42, taskDescription: "do a thing")

        #expect(status.iterationRecords.last?.endDate == nil)

        status.applyIteration(count: 1, passes: [true])

        #expect(status.iterationRecords.last?.endDate != nil)
    }

    @Test("applyIteration stamps endDate only on current record, not a later one")
    func applyIterationDoesNotStampNextRecord() async throws {
        let status = SessionRunStatus()
        status.beginIteration(number: 1, taskID: 1, taskDescription: "first")
        status.applyIteration(count: 1, passes: [false])

        // Begin second iteration before asserting — endDate must be on record 1 only
        status.beginIteration(number: 2, taskID: 2, taskDescription: "second")

        #expect(status.iterationRecords[0].endDate != nil)
        #expect(status.iterationRecords[1].endDate == nil)
    }

    @Test("applyIteration on empty records is a no-op")
    func applyIterationEmptyRecords() async {
        let status = SessionRunStatus()
        // Should not crash
        status.applyIteration(count: 0, passes: [])
        #expect(status.iterationRecords.isEmpty)
    }
}
