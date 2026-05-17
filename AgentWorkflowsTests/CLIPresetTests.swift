import Testing
import Foundation
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

    @Test func piIsEnumerated() {
        #expect(CLIPreset.allCases.contains(.pi))
    }

    @Test func openCodeIsEnumerated() {
        #expect(CLIPreset.allCases.contains(.openCode))
    }

    @Test func codexRecipeLaunchesCodexFullAutoForTerminalPlan() {
        let recipe = CLIPreset.codex.invocationRecipe
        #expect(recipe?.binaryName == "codex")
        #expect(recipe?.terminalArgs == ["--full-auto"])
    }

    @Test func piRecipeLaunchesPiWithoutDefaultArgs() {
        let recipe = CLIPreset.pi.invocationRecipe
        #expect(recipe?.binaryName == "pi")
        #expect(recipe?.terminalArgs == [])
    }

    @Test func openCodeRecipeLaunchesOpenCodeWithoutDefaultArgs() {
        let recipe = CLIPreset.openCode.invocationRecipe
        #expect(recipe?.binaryName == "opencode")
        #expect(recipe?.terminalArgs == [])
    }

    @Test func claudeRecipeUsesAcceptEditsForInteractiveTerminal() {
        #expect(CLIPreset.claude.invocationRecipe?.terminalArgs == ["--permission-mode", "acceptEdits"])
    }

    @Test func piSkillsDirectoryPointsToAgentsSkills() {
        let path = CLIPreset.pi.skillsDirectory?.path
        #expect(path?.hasSuffix(".agents/skills") == true)
    }

    @Test func openCodeSkillsDirectoryPointsToOpenCodeCommands() {
        let path = CLIPreset.openCode.skillsDirectory?.path
        #expect(path?.hasSuffix(".config/opencode/commands") == true)
    }

    @Test func allSkillsDirectoriesDeduplicatesWhenAllPresetsSame() {
        let settings = Settings(
            sidebarTitleProvider: .pi,
            planCLI: .pi,
            verifyCLI: .pi,
            buildCLI: .pi
        )
        #expect(settings.allSkillsDirectories.count == 1)
        #expect(settings.allSkillsDirectories.first?.path.hasSuffix(".agents/skills") == true)
    }

    @Test func skillTargetPiPointsToAgentsSkills() {
        #expect(SkillTarget.pi.directory.path.hasSuffix(".agents/skills"))
    }

    @Test func skillTargetClaudeAndCodexPathsAreUnchanged() {
        #expect(SkillTarget.claude.directory.path.hasSuffix(".claude/skills"))
        #expect(SkillTarget.codex.directory.path.hasSuffix(".codex/skills"))
    }

    @Test func skillTargetOpenCodePointsToCommandsDirectory() {
        #expect(SkillTarget.openCode.directory.path.hasSuffix(".config/opencode/commands"))
    }

    @Test func defaultSettingsResolvesAllFieldsToClaude() {
        let settings = Settings.default
        #expect(settings.sidebarTitleProvider == .claude)
        #expect(settings.sidebarTitleCLI == .claude)
        #expect(settings.planCLI == .claude)
        #expect(settings.verifyCLI == .claude)
        #expect(settings.buildCLI == .claude)
    }

    @Test func foundationModelsTitleProviderHasNoSkillsDirectory() {
        let settings = Settings(
            sidebarTitleProvider: .foundationModels,
            planCLI: .claude,
            verifyCLI: .claude,
            buildCLI: .claude
        )
        #expect(settings.allSkillsDirectories.contains(CLIPreset.claude.skillsDirectory!) == true)
        #expect(settings.allSkillsDirectories.contains(CLIPreset.codex.skillsDirectory!) == false)
    }

    @Test func legacySidebarTitleCLIDecodesAsProvider() throws {
        let json = #"{"sidebarTitleCLI":"codex","planCLI":"claude","verifyCLI":"claude","buildCLI":"claude"}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.sidebarTitleProvider == .codex)
        #expect(settings.sidebarTitleCLI == .codex)
    }

    @Test func sidebarTitleProviderPiDisplayNameIsPiCLI() {
        #expect(SidebarTitleProvider.pi.displayName == "Pi CLI")
    }

    @Test func sidebarTitleProviderPiMapsToPiPreset() {
        #expect(SidebarTitleProvider.pi.cliPreset == .pi)
        #expect(SidebarTitleProvider.cli(.pi) == .pi)
    }

    @Test func sidebarTitleProviderOpenCodeDisplayNameIsOpenCodeCLI() {
        #expect(SidebarTitleProvider.openCode.displayName == "OpenCode CLI")
    }

    @Test func sidebarTitleProviderOpenCodeMapsToOpenCodePreset() {
        #expect(SidebarTitleProvider.openCode.cliPreset == .openCode)
        #expect(SidebarTitleProvider.cli(.openCode) == .openCode)
    }

    @Test func piPresetRoundTripsViaJSON() throws {
        let original = Settings(
            sidebarTitleProvider: .pi,
            planCLI: .pi,
            verifyCLI: .pi,
            buildCLI: .pi
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded == original)
    }

    @Test func openCodePresetRoundTripsViaJSON() throws {
        let original = Settings(
            sidebarTitleProvider: .foundationModels,
            planCLI: .openCode,
            verifyCLI: .openCode,
            buildCLI: .openCode
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded == original)
    }

    @Test func allSkillsDirectoriesDeduplicatesWhenAllPresetsOpenCode() {
        let settings = Settings(
            sidebarTitleProvider: .foundationModels,
            planCLI: .openCode,
            verifyCLI: .openCode,
            buildCLI: .openCode
        )
        #expect(settings.allSkillsDirectories.count == 1)
        #expect(settings.allSkillsDirectories.first?.path.hasSuffix(".config/opencode/commands") == true)
    }

    @Test func settingsDecodeSupportsRawOpenCodeString() throws {
        let preset = try JSONDecoder().decode(CLIPreset.self, from: Data(#""openCode""#.utf8))
        #expect(preset == .openCode)
    }

    @Test func sidebarTitleProviderOpenCodeRoundTripsViaJSON() throws {
        let provider = SidebarTitleProvider.openCode
        let data = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(SidebarTitleProvider.self, from: data)
        #expect(decoded == provider)
    }

    @Test func settingsWithUnknownCLIFallsBackToDefault() throws {
        let json = #"{"sidebarTitleProvider":"unknown_future_provider","planCLI":"unknown_future_cli","verifyCLI":"unknown_future_cli","buildCLI":"unknown_future_cli"}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.sidebarTitleProvider == .claude)
        #expect(settings.planCLI == .claude)
        #expect(settings.verifyCLI == .claude)
        #expect(settings.buildCLI == .claude)
    }
}
