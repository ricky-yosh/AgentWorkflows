import Testing
import Foundation
@testable import AgentWorkflows

struct CLIToolDefinitionTests {

    @Test func codableRoundTrip() throws {
        let tool = CLIToolDefinition(name: "claude", command: "claude", defaultArgs: ["--dangerously-skip-permissions"])
        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(CLIToolDefinition.self, from: data)
        #expect(decoded == tool)
    }

    @Test func decodesSnakeCaseDefaultArgs() throws {
        let json = Data(#"{"name":"claude","command":"claude","default_args":["--verbose"]}"#.utf8)
        let tool = try JSONDecoder().decode(CLIToolDefinition.self, from: json)
        #expect(tool.name == "claude")
        #expect(tool.defaultArgs == ["--verbose"])
    }

    @Test func decodesWithoutDefaultArgs() throws {
        let json = Data(#"{"name":"bash","command":"/bin/bash"}"#.utf8)
        let tool = try JSONDecoder().decode(CLIToolDefinition.self, from: json)
        #expect(tool.defaultArgs == nil)
    }
}
