import Foundation
import Testing
@testable import AgentWorkflows

struct DigestProviderTests {
    @Test func resolvePromptTemplate() {
        let template = "Summarize: {content}"
        let content = "Hello world"
        let resolved = template.replacingOccurrences(of: "{content}", with: content)
        #expect(resolved == "Summarize: Hello world")
    }

    @Test func cliToolsThrowNotImplemented() async {
        let tool = CLIToolDefinition(name: "claude", command: "claude", defaultArgs: nil)

        do {
            _ = try await DigestService.generate(
                content: "test",
                promptTemplate: "{content}",
                tool: tool
            )
            Issue.record("Expected error")
        } catch DigestError.notImplemented(let name) {
            #expect(name == "CLI tools cannot generate digests")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
