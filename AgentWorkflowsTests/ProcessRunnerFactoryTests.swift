import Testing
@testable import AgentWorkflows

@Suite("ProcessRunnerFactory")
struct ProcessRunnerFactoryTests {

    @Test func claudePresetReturnsClaudeProcessRunner() throws {
        let runner = try ProcessRunnerFactory.make(preset: .claude)
        #expect(runner is ClaudeProcessRunner)
    }

    @Test func codexPresetReturnsCodexProcessRunner() throws {
        let runner = try ProcessRunnerFactory.make(preset: .codex)
        #expect(runner is CodexProcessRunner)
    }

    @Test func codexPresetTitleBackendThrowsUnavailable() {
        #expect(throws: ProcessRunnerFactoryError.unavailable(.codex)) {
            try ProcessRunnerFactory.makeTitleBackend(preset: .codex)
        }
    }
}
