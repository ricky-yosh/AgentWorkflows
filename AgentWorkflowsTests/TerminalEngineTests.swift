import Testing
import Foundation
@testable import AgentWorkflows

@Suite("TerminalEngine")
struct TerminalEngineTests {

    // MARK: - normalizeTerminator

    @Test func normalizeLeavesTextWithoutNewlineUnchanged_addsCR() {
        let result = TerminalEngine.normalizeTerminator("hello")
        #expect(result == "hello\r")
    }

    @Test func normalizeStripsTrailingNewlineAndAddsCR() {
        let result = TerminalEngine.normalizeTerminator("hello\n")
        #expect(result == "hello\r")
    }

    @Test func normalizeStripsTrailingCRAndReplacesWithCR() {
        let result = TerminalEngine.normalizeTerminator("hello\r")
        #expect(result == "hello\r")
    }

    @Test func normalizeStripsMultipleTrailingNewlines() {
        let result = TerminalEngine.normalizeTerminator("hello\n\n")
        #expect(result == "hello\r")
    }

    @Test func normalizePreservesInternalNewlines() {
        let result = TerminalEngine.normalizeTerminator("line1\nline2\n")
        #expect(result == "line1\nline2\r")
    }

    // MARK: - bytesForPTY terminator assertion

    @Test func bytesForPTYTerminatorIsCarriageReturn_withNewline() {
        let bytes = TerminalEngine.bytesForPTY(TerminalEngine.normalizeTerminator("hello\n"))
        #expect(bytes.last == 0x0D)
    }

    @Test func bytesForPTYTerminatorIsCarriageReturn_withoutNewline() {
        let bytes = TerminalEngine.bytesForPTY(TerminalEngine.normalizeTerminator("hello"))
        #expect(bytes.last == 0x0D)
    }

    @Test func bytesForPTYTerminatorIsCarriageReturn_multiLine() {
        let bytes = TerminalEngine.bytesForPTY(TerminalEngine.normalizeTerminator("line1\nline2\n"))
        #expect(bytes.last == 0x0D)
    }
}
