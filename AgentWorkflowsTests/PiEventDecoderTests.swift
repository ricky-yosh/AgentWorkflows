import Testing
@testable import AgentWorkflows

@Suite("PiEventDecoder")
struct PiEventDecoderTests {

    typealias Decoder = PiEventDecoder

    @Test func messageUpdateTextDeltaEmitsAssistantText() {
        let line = #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"hello"},"partial":"ignored","message":{"content":"snapshot"}}"#
        let events = Decoder().decode(line)
        #expect(events == [.assistantText("hello")])
    }

    @Test func messageUpdateNonTextDeltaEmitsNoEvent() {
        let line = #"{"type":"message_update","assistantMessageEvent":{"type":"tool_call","delta":"ignored"}}"#
        let events = Decoder().decode(line)
        #expect(events.isEmpty)
    }

    @Test func toolExecutionStartEmitsToolUse() {
        let line = #"{"type":"tool_execution_start","tool":"Bash","input":{"cmd":"ls -la"}}"#
        let events = Decoder().decode(line)
        guard case .toolUse(let name, let summary) = events.first else {
            Issue.record("Expected toolUse event"); return
        }
        #expect(name == "Bash")
        #expect(summary.contains("\"cmd\":\"ls -la\""))
    }

    @Test func toolExecutionEndEmitsToolResult() {
        let line = #"{"type":"tool_execution_end","output":"done","success":true}"#
        let events = Decoder().decode(line)
        #expect(events == [.toolResult(summary: "done", failed: false)])
    }

    @Test func agentEndEmitsIterationFinished() {
        let line = #"{"type":"agent_end","result":"completed"}"#
        let events = Decoder().decode(line)
        #expect(events == [.iterationFinished(result: "completed")])
    }

    @Test func firstMessageStartEmitsModelIdentifiedFromTopLevelFields() {
        let decoder = Decoder()
        let first = decoder.decode(#"{"type":"message_start","provider":"mlx","model":"Qwen3-Coder"}"#)
        let second = decoder.decode(#"{"type":"message_start","provider":"ollama","model":"deepseek"}"#)
        #expect(first == [.modelIdentified(provider: "mlx", model: "Qwen3-Coder")])
        #expect(second.isEmpty)
    }

    @Test func messageStartAlsoSupportsNestedMessageFields() {
        let events = Decoder().decode(#"{"type":"message_start","message":{"provider":"mlx","model":"Qwen3-Coder"}}"#)
        #expect(events == [.modelIdentified(provider: "mlx", model: "Qwen3-Coder")])
    }

    @Test func messageStartWithoutProviderOrModelEmitsNoEvent() {
        let decoder = Decoder()
        #expect(decoder.decode(#"{"type":"message_start","provider":"mlx"}"#).isEmpty)
        #expect(decoder.decode(#"{"type":"message_start","model":"Qwen3-Coder"}"#).isEmpty)
    }

    @Test func malformedJsonLineProducesNoEventsAndNoCrash() {
        let decoder = Decoder()
        let events = decoder.decode("{bad json")
        #expect(events.isEmpty)
        #expect(decoder.malformedCount == 1)
    }

    @Test func textDeltaIgnoresSnapshotFieldsAndUsesOnlyDelta() {
        let line = #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"d"},"partial":"SHOULD_NOT_APPEAR","message":{"content":"SHOULD_NOT_APPEAR"}}"#
        let events = Decoder().decode(line)
        #expect(events == [.assistantText("d")])
    }
}
