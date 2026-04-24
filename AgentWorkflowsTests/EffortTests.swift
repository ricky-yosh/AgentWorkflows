import Testing
@testable import AgentWorkflows

@Suite("Effort")
struct EffortTests {

    // MARK: - rawValue

    @Test func rawValueMatchesArgvFlag() {
        #expect(Effort.low.rawValue == "low")
        #expect(Effort.medium.rawValue == "medium")
        #expect(Effort.high.rawValue == "high")
    }

    // MARK: - Passthrough

    @Test func lowPassesThrough() {
        #expect(Effort(raw: "low") == .low)
    }

    @Test func mediumPassesThrough() {
        #expect(Effort(raw: "medium") == .medium)
    }

    @Test func highPassesThrough() {
        #expect(Effort(raw: "high") == .high)
    }

    // MARK: - Clamp to high

    @Test func xhighClampsToHigh() {
        #expect(Effort(raw: "xhigh") == .high)
    }

    @Test func maxClampsToHigh() {
        #expect(Effort(raw: "max") == .high)
    }

    // MARK: - Default to medium

    @Test func nilDefaultsToMedium() {
        #expect(Effort(raw: nil) == .medium)
    }

    @Test func emptyStringDefaultsToMedium() {
        #expect(Effort(raw: "") == .medium)
    }

    @Test func whitespaceOnlyDefaultsToMedium() {
        #expect(Effort(raw: "   ") == .medium)
    }

    @Test func unrecognizedGarbageDefaultsToMedium() {
        #expect(Effort(raw: "huge") == .medium)
    }

    // MARK: - Case sensitivity (behavior decision: exact lowercase match only)

    @Test func uppercaseLowDefaultsToMedium() {
        #expect(Effort(raw: "LOW") == .medium)
    }

    @Test func mixedCaseHighDefaultsToMedium() {
        #expect(Effort(raw: "High") == .medium)
    }
}
