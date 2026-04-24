import Testing
@testable import AgentWorkflows

@Suite("CodexEventDecoder")
struct CodexEventDecoderTests {

    typealias Decoder = CodexEventDecoder
    typealias Event = IterationEvent

    // MARK: - sessionStarted

    @Test func threadStartedEmitsSessionStarted() {
        let events = Decoder().decode(CodexFixtures.threadStarted)
        #expect(events == [.sessionStarted(sessionId: "019db813-020c-7613-b8e6-1cf640f5365b")])
    }

    // MARK: - turn.started (dropped)

    @Test func turnStartedIsDroppedSilently() {
        let decoder = Decoder()
        let events = decoder.decode(CodexFixtures.turnStarted)
        #expect(events.isEmpty)
        #expect(decoder.malformedCount == 0)
    }

    // MARK: - assistantText

    @Test func agentMessageCompletedEmitsAssistantText() {
        let events = Decoder().decode(CodexFixtures.agentMessageCompleted)
        #expect(events == [.assistantText("I'm executing the three requested shell actions in order, then I'll confirm completion.")])
    }

    // MARK: - toolUse (command_execution)

    @Test func commandStartedEmitsToolUse() {
        let events = Decoder().decode(CodexFixtures.commandStarted)
        guard case .toolUse(let name, let summary) = events.first else {
            Issue.record("Expected toolUse event"); return
        }
        #expect(name == "bash")
        #expect(summary.contains("echo hello"))
    }

    @Test func commandToolUseInputTruncatedTo140() {
        let longCmd = String(repeating: "x", count: 200)
        let line = #"{"type":"item.started","item":{"id":"i","type":"command_execution","command":""# + longCmd + #"","aggregated_output":"","exit_code":null,"status":"in_progress"}}"#
        let events = Decoder().decode(line)
        guard case .toolUse(_, let summary) = events.first else {
            Issue.record("Expected toolUse event"); return
        }
        #expect(summary.count <= 140)
    }

    // MARK: - toolResult (command_execution success)

    @Test func commandCompletedSuccessEmitsToolResult() {
        let events = Decoder().decode(CodexFixtures.commandCompletedSuccess)
        #expect(events == [.toolResult(summary: "hello ", failed: false)])
    }

    // MARK: - toolResult (command_execution failure)

    @Test func commandCompletedFailureEmitsToolResultFailed() {
        let events = Decoder().decode(CodexFixtures.commandCompletedFailure)
        #expect(events == [.toolResult(summary: "", failed: true)])
    }

    @Test func commandCompletedNonzeroExitIsFailed() {
        let line = #"{"type":"item.completed","item":{"id":"i","type":"command_execution","command":"false","aggregated_output":"","exit_code":2,"status":"completed"}}"#
        let events = Decoder().decode(line)
        guard case .toolResult(_, let failed) = events.first else {
            Issue.record("Expected toolResult event"); return
        }
        #expect(failed == true)
    }

    @Test func commandCompletedOutputNewlinesReplacedWithSpaces() {
        let line = #"{"type":"item.completed","item":{"id":"i","type":"command_execution","command":"cmd","aggregated_output":"line1\nline2","exit_code":0,"status":"completed"}}"#
        let events = Decoder().decode(line)
        #expect(events == [.toolResult(summary: "line1 line2", failed: false)])
    }

    @Test func commandCompletedOutputTruncatedTo200() {
        let output = String(repeating: "y", count: 300)
        let line = #"{"type":"item.completed","item":{"id":"i","type":"command_execution","command":"cmd","aggregated_output":""# + output + #"","exit_code":0,"status":"completed"}}"#
        let events = Decoder().decode(line)
        guard case .toolResult(let summary, _) = events.first else {
            Issue.record("Expected toolResult event"); return
        }
        #expect(summary.count <= 200)
    }

    // MARK: - toolUse (file_change)

    @Test func fileChangeStartedEmitsToolUseEdit() {
        let events = Decoder().decode(CodexFixtures.fileChangeStarted)
        guard case .toolUse(let name, let summary) = events.first else {
            Issue.record("Expected toolUse event"); return
        }
        #expect(name == "Edit")
        #expect(summary.contains("add"))
        #expect(summary.contains("/tmp/codex_filechange_demo.txt"))
    }

    // MARK: - toolResult (file_change)

    @Test func fileChangeCompletedEmitsToolResultOk() {
        let events = Decoder().decode(CodexFixtures.fileChangeCompleted)
        #expect(events == [.toolResult(summary: "ok", failed: false)])
    }

    // MARK: - iterationFinished

    @Test func turnCompletedEmitsIterationFinishedWithLastAgentText() {
        let decoder = Decoder()
        _ = decoder.decode(CodexFixtures.agentMessageCompleted)
        let events = decoder.decode(CodexFixtures.turnCompleted)
        #expect(events == [.iterationFinished(result: "I'm executing the three requested shell actions in order, then I'll confirm completion.")])
    }

    @Test func turnCompletedWithoutPriorAgentMessageUsesEmptyString() {
        let decoder = Decoder()
        let events = decoder.decode(CodexFixtures.turnCompleted)
        #expect(events == [.iterationFinished(result: "")])
    }

    // MARK: - Unknown frame types (silently dropped)

    @Test func unknownTypeDroppedSilently() {
        let decoder = Decoder()
        let events = decoder.decode(#"{"type":"turn.progress","delta":"x"}"#)
        #expect(events.isEmpty)
        #expect(decoder.malformedCount == 0)
    }

    @Test func validJsonWithoutTypeDroppedSilently() {
        let decoder = Decoder()
        let events = decoder.decode(#"{"foo":"bar"}"#)
        #expect(events.isEmpty)
        #expect(decoder.malformedCount == 0)
    }

    // MARK: - Malformed JSON

    @Test func malformedJsonIncrementsMalformedCount() {
        let decoder = Decoder()
        let events = decoder.decode("not valid json {{{")
        #expect(events.isEmpty)
        #expect(decoder.malformedCount == 1)
    }

    @Test func multipleMalformedLinesAccumulate() {
        let decoder = Decoder()
        _ = decoder.decode("bad line 1")
        _ = decoder.decode("bad line 2")
        #expect(decoder.malformedCount == 2)
    }

    @Test func emptyLineDoesNotIncrementMalformedCount() {
        let decoder = Decoder()
        _ = decoder.decode("")
        _ = decoder.decode("   ")
        #expect(decoder.malformedCount == 0)
    }

    // MARK: - Table-driven: each fixture maps to expected event list

    @Test(
        "fixture event mapping",
        arguments: [
            (
                CodexFixtures.threadStarted,
                [IterationEvent.sessionStarted(sessionId: "019db813-020c-7613-b8e6-1cf640f5365b")]
            ),
            (
                CodexFixtures.turnStarted,
                [] as [IterationEvent]
            ),
            (
                CodexFixtures.agentMessageCompleted,
                [IterationEvent.assistantText("I'm executing the three requested shell actions in order, then I'll confirm completion.")]
            ),
            (
                CodexFixtures.commandCompletedSuccess,
                [IterationEvent.toolResult(summary: "hello ", failed: false)]
            ),
            (
                CodexFixtures.commandCompletedFailure,
                [IterationEvent.toolResult(summary: "", failed: true)]
            ),
            (
                CodexFixtures.fileChangeCompleted,
                [IterationEvent.toolResult(summary: "ok", failed: false)]
            ),
        ] as [(String, [IterationEvent])]
    )
    func fixtureEventMapping(line: String, expected: [IterationEvent]) {
        let events = Decoder().decode(line)
        #expect(events == expected)
    }
}
