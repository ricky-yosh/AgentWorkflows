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

    @Test func piMakeReturnsAPiProcessRunner() throws {
        let runner = try ProcessRunnerFactory.make(preset: .pi)
        #expect(runner is PiProcessRunner)
    }

    @Test func openCodePresetReturnsOpenCodeProcessRunner() throws {
        let runner = try ProcessRunnerFactory.make(preset: .openCode)
        #expect(runner is OpenCodeProcessRunner)
    }

    @Test func codexPresetTitleBackendThrowsUnavailable() {
        #expect(throws: ProcessRunnerFactoryError.unavailable(.codex)) {
            try ProcessRunnerFactory.makeTitleBackend(preset: .codex)
        }
    }

    @Test func openCodePresetTitleBackendThrowsUnavailable() {
        #expect(throws: ProcessRunnerFactoryError.unavailable(.openCode)) {
            try ProcessRunnerFactory.makeTitleBackend(preset: .openCode)
        }
    }

    @Test func piMakeTitleBackendSucceeds() throws {
        let backend = try ProcessRunnerFactory.makeTitleBackend(preset: .pi)
        #expect(backend is CLISubprocessTitleBackend)
    }

    @Test func piProviderMakeTitleBackendSucceeds() throws {
        let backend = try ProcessRunnerFactory.makeTitleBackend(provider: .pi)
        #expect(backend is CLISubprocessTitleBackend)
    }

    @Test func foundationModelsProviderReturnsFoundationModelsTitleBackend() throws {
        let backend = try ProcessRunnerFactory.makeTitleBackend(provider: .foundationModels)
        #expect(backend is FoundationModelsTitleBackend)
    }

    @Test func codexToolIdentifierResolvesToCodexTerminalDefinition() {
        let tool = ProcessRunnerFactory.toolIdentifier(for: .codex)
        let definition = EngineManager.toolDefinition(for: tool)
        #expect(definition?.command == "codex")
        #expect(definition?.defaultArgs == ["--full-auto"])
    }

    @Test func piToolIdentifierResolvesToPiTerminalDefinition() {
        let tool = ProcessRunnerFactory.toolIdentifier(for: .pi)
        let definition = EngineManager.toolDefinition(for: tool)
        #expect(definition?.command == "pi")
        #expect(definition?.defaultArgs == [])
    }

    @Test func openCodeToolIdentifierResolvesToOpenCodeTerminalDefinition() {
        let tool = ProcessRunnerFactory.toolIdentifier(for: .openCode)
        let definition = EngineManager.toolDefinition(for: tool)
        #expect(definition?.command == "opencode")
        #expect(definition?.defaultArgs == [])
    }
}
