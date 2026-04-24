import Testing
@testable import AgentWorkflows

@Suite("StreamJsonDecoder")
struct StreamJsonDecoderTests {

    typealias Decoder = StreamJsonDecoder
    typealias Event = IterationEvent

    // MARK: - sessionStarted

    @Test func sessionStartedEmitted() {
        let line = #"{"type":"system","subtype":"init","session_id":"abc-123"}"#
        let events = Decoder().decode(line)
        #expect(events == [.sessionStarted(sessionId: "abc-123")])
    }

    @Test func systemNonInitDroppedSilently() {
        let decoder = Decoder()
        let line = #"{"type":"system","subtype":"other","session_id":"abc-123"}"#
        let events = decoder.decode(line)
        #expect(events.isEmpty)
        #expect(decoder.malformedCount == 0)
    }

    // MARK: - assistantText

    @Test func assistantTextEmitted() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello!"}]}}"#
        let events = Decoder().decode(line)
        #expect(events == [.assistantText("Hello!")])
    }

    // MARK: - toolUse

    @Test func toolUseEmitted() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#
        let events = Decoder().decode(line)
        guard case .toolUse(let name, let summary) = events.first else {
            Issue.record("Expected toolUse event"); return
        }
        #expect(name == "Bash")
        #expect(summary.contains("ls"))
    }

    @Test func toolUseInputTruncatedTo140() {
        let cmd = String(repeating: "a", count: 200)
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"cmd":""# + cmd + #""}}]}}"#
        let events = Decoder().decode(line)
        guard case .toolUse(_, let summary) = events.first else {
            Issue.record("Expected toolUse event"); return
        }
        #expect(summary.count <= 140)
    }

    // MARK: - toolResult

    @Test func toolResultStringContentEmitted() {
        let line = #"{"type":"user","message":{"content":[{"type":"tool_result","content":"output here"}]}}"#
        let events = Decoder().decode(line)
        #expect(events == [.toolResult(summary: "output here", failed: false)])
    }

    @Test func toolResultArrayContentJoined() {
        let line = #"{"type":"user","message":{"content":[{"type":"tool_result","content":[{"type":"text","text":"part one"},{"type":"text","text":"part two"}]}]}}"#
        let events = Decoder().decode(line)
        #expect(events == [.toolResult(summary: "part one part two", failed: false)])
    }

    @Test func toolResultTruncatedTo200() {
        let content = String(repeating: "y", count: 300)
        let line = #"{"type":"user","message":{"content":[{"type":"tool_result","content":""# + content + #""}]}}"#
        let events = Decoder().decode(line)
        guard case .toolResult(let summary, let failed) = events.first else {
            Issue.record("Expected toolResult event"); return
        }
        #expect(summary.count <= 200)
        #expect(failed == false)
    }

    @Test func toolResultNewlinesReplacedWithSpaces() {
        let line = "{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"content\":\"line1\\nline2\"}]}}"
        let events = Decoder().decode(line)
        #expect(events == [.toolResult(summary: "line1 line2", failed: false)])
    }

    // MARK: - iterationFinished

    @Test func iterationFinishedEmitted() {
        let line = #"{"type":"result","subtype":"success","result":"success"}"#
        let events = Decoder().decode(line)
        #expect(events == [.iterationFinished(result: "success")])
    }

    @Test func iterationFinishedWithoutResultFieldUsesEmptyString() {
        let line = #"{"type":"result","subtype":"success"}"#
        let events = Decoder().decode(line)
        #expect(events == [.iterationFinished(result: "")])
    }

    // MARK: - Multiple content items in one frame

    @Test func assistantMultipleContentItemsEmitsMultipleEvents() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"thinking..."},{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/x"}}]}}"#
        let events = Decoder().decode(line)
        #expect(events.count == 2)
        #expect(events[0] == .assistantText("thinking..."))
        guard case .toolUse(let name, _) = events[1] else {
            Issue.record("Expected toolUse as second event"); return
        }
        #expect(name == "Read")
    }

    // MARK: - Unknown frame types (silently dropped, no count increment)

    @Test func unknownTypeDroppedSilently() {
        let decoder = Decoder()
        let line = #"{"type":"progress","percent":50}"#
        let events = decoder.decode(line)
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

    @Test func validJsonAfterMalformedDoesNotAccumulate() {
        let decoder = Decoder()
        _ = decoder.decode("not json")
        _ = decoder.decode(#"{"type":"result"}"#)
        #expect(decoder.malformedCount == 1)
    }

    // MARK: - Table-driven: each event variant

    @Test(
        "event variants",
        arguments: [
            (
                #"{"type":"system","subtype":"init","session_id":"s1"}"#,
                [IterationEvent.sessionStarted(sessionId: "s1")]
            ),
            (
                #"{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}"#,
                [IterationEvent.assistantText("hi")]
            ),
            (
                #"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#,
                [IterationEvent.toolResult(summary: "ok", failed: false)]
            ),
            (
                #"{"type":"result","result":"success"}"#,
                [IterationEvent.iterationFinished(result: "success")]
            ),
        ] as [(String, [IterationEvent])]
    )
    func eventVariants(line: String, expected: [IterationEvent]) {
        let events = Decoder().decode(line)
        #expect(events == expected)
    }
}
