import Testing
@testable import AgentWorkflows

@Suite("CLIPreset")
struct CLIPresetTests {

    @Test func claudeRecipeHasCorrectBinaryName() {
        let recipe = CLIPreset.claude.invocationRecipe
        #expect(recipe != nil)
        #expect(recipe?.binaryName == "claude")
    }

    @Test func claudeRecipeIncludesStreamJsonOutputFormat() {
        let flags = CLIPreset.claude.invocationRecipe?.streamingFlags ?? []
        #expect(flags.contains("--output-format"))
        #expect(flags.contains("stream-json"))
    }

    @Test func codexIsEnumerated() {
        #expect(CLIPreset.allCases.contains(.codex))
    }

    @Test func codexCarriesNoRunnerHook() {
        #expect(CLIPreset.codex.invocationRecipe == nil)
    }

    @Test func defaultSettingsResolvesAllFieldsToClaude() {
        let settings = Settings.default
        #expect(settings.sidebarTitleCLI == .claude)
        #expect(settings.planCLI == .claude)
        #expect(settings.verifyCLI == .claude)
        #expect(settings.buildCLI == .claude)
    }
}
