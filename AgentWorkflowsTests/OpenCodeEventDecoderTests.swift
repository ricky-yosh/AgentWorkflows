import Testing
@testable import AgentWorkflows

@Suite("OpenCodeEventDecoder")
struct OpenCodeEventDecoderTests {

    typealias Decoder = OpenCodeEventDecoder

    @Test func stepStartEmitsSessionStarted() {
        let line = #"{"type":"step_start","session_id":"sess-123"}"#
        let events = Decoder().decode(line)
        #expect(events == [.sessionStarted(sessionId: "sess-123")])
    }

    @Test func textEmitsAssistantText() {
        let line = #"{"type":"text","text":"hello"}"#
        let events = Decoder().decode(line)
        #expect(events == [.assistantText("hello")])
    }

    @Test func nestedPartTextEmitsAssistantText() {
        let line = #"{"type":"text","timestamp":1777245701917,"sessionID":"ses_1","part":{"type":"text","text":"Now let me commit and update the task state."}}"#
        let events = Decoder().decode(line)
        #expect(events == [.assistantText("Now let me commit and update the task state.")])
    }

    @Test func runningToolUseEmitsToolUse() {
        let line = #"{"type":"tool_use","name":"bash","input":{"cmd":"ls -la"},"state":{"status":"running"}}"#
        let events = Decoder().decode(line)
        guard case .toolUse(let name, let summary) = events.first else {
            Issue.record("Expected toolUse event"); return
        }
        #expect(name == "bash")
        #expect(summary.contains("\"cmd\":\"ls -la\""))
    }

    @Test func completedToolUseEmitsSuccessfulToolResult() {
        let line = #"{"type":"tool_use","name":"bash","output":"done","state":{"status":"completed"}}"#
        let events = Decoder().decode(line)
        #expect(events == [.toolResult(summary: "done", failed: false)])
    }

    @Test func nestedCompletedToolUseEmitsSuccessfulToolResult() {
        let line = #"{"type":"tool_use","timestamp":1777245702111,"sessionID":"ses_1","part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"git status"},"output":"On branch main\nnothing to commit"}}}"#
        let events = Decoder().decode(line)
        #expect(events == [.toolResult(summary: "On branch main nothing to commit", failed: false)])
    }

    @Test func nestedRunningToolUseEmitsToolUse() {
        let line = #"{"type":"tool_use","sessionID":"ses_1","part":{"type":"tool","tool":"read","state":{"status":"running","input":{"filePath":"/tmp/tasks.json"}}}}"#
        let events = Decoder().decode(line)
        guard case .toolUse(let name, let summary) = events.first else {
            Issue.record("Expected toolUse event"); return
        }
        #expect(name == "read")
        #expect(summary.contains("tasks.json"))
    }

    @Test func failedToolUseEmitsFailedToolResult() {
        let line = #"{"type":"tool_use","name":"bash","output":"boom","state":{"status":"failed"}}"#
        let events = Decoder().decode(line)
        #expect(events == [.toolResult(summary: "boom", failed: true)])
    }

    @Test func nestedErrorToolUseEmitsFailedToolResult() {
        let line = #"{"type":"tool_use","sessionID":"ses_1","part":{"type":"tool","tool":"read","state":{"status":"error","input":{"filePath":"/tmp/progress.txt"},"error":"File not found: /tmp/progress.txt"}}}"#
        let events = Decoder().decode(line)
        #expect(events == [.toolResult(summary: "File not found: /tmp/progress.txt", failed: true)])
    }

    @Test func stepFinishStopEmitsIterationFinished() {
        let line = #"{"type":"step_finish","reason":"stop"}"#
        let events = Decoder().decode(line)
        #expect(events == [.iterationFinished(result: "")])
    }

    @Test func nestedStepFinishStopEmitsIterationFinished() {
        let line = #"{"type":"step_finish","sessionID":"ses_1","part":{"reason":"stop","tokens":{"total":42623}}}"#
        let events = Decoder().decode(line)
        #expect(events == [.iterationFinished(result: "")])
    }

    @Test func errorEmitsIterationFinishedWithErrorMessage() {
        let line = #"{"type":"error","message":"fatal: out of tokens"}"#
        let events = Decoder().decode(line)
        #expect(events == [.iterationFinished(result: "fatal: out of tokens")])
    }

    @Test func malformedJsonIncrementsCountAndEmitsNothing() {
        let decoder = Decoder()
        let events = decoder.decode("{bad json")
        #expect(events.isEmpty)
        #expect(decoder.malformedCount == 1)
    }

    @Test func modelIdentifiedIsNeverEmitted() {
        let decoder = Decoder()
        let lines = [
            #"{"type":"step_start","session_id":"sess-123","provider":"ollama","model":"qwen"}"#,
            #"{"type":"text","text":"hi","provider":"ollama","model":"qwen"}"#,
            #"{"type":"tool_use","name":"bash","input":{"cmd":"pwd"},"state":{"status":"running"},"provider":"ollama","model":"qwen"}"#,
        ]

        for line in lines {
            let events = decoder.decode(line)
            for event in events {
                switch event {
                case .modelIdentified:
                    Issue.record("OpenCodeEventDecoder should never emit modelIdentified")
                default:
                    break
                }
            }
        }
    }
}
