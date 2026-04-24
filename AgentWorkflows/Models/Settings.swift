import Foundation

// MARK: - CLIPreset

/// The known AI CLI tools the app can invoke for subprocesses.
nonisolated enum CLIPreset: String, CaseIterable, Codable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    /// Everything needed to spawn a streaming subprocess for this CLI.
    struct InvocationRecipe {
        let binaryName: String
        let streamingFlags: [String]
    }

    /// Returns the invocation recipe for this preset, or `nil` if the runner builds its own argv.
    /// `codex` assembles its own argv in `CodexProcessRunner` and does not use this recipe.
    var invocationRecipe: InvocationRecipe? {
        switch self {
        case .claude:
            return InvocationRecipe(
                binaryName: "claude",
                streamingFlags: [
                    "-p",
                    "--permission-mode", "acceptEdits",
                    "--model", "sonnet",
                    "--output-format", "stream-json",
                    "--verbose"
                ]
            )
        case .codex:
            return nil
        }
    }

    /// The directory where this CLI reads and writes skill files, or `nil` if the CLI has no skills concept.
    var skillsDirectory: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude:
            return home.appendingPathComponent(".claude/skills", isDirectory: true)
        case .codex:
            return home.appendingPathComponent(".codex/skills", isDirectory: true)
        // case .opencode:
        //     return home.appendingPathComponent(".config/opencode/skills", isDirectory: true)
        // case .pi:
        //     return home.appendingPathComponent(".agents/skills", isDirectory: true)
        }
    }
}

// MARK: - Settings

/// The effective configuration for the app — one `CLIPreset` per subprocess call site.
/// Immutable value type; mutations go through `SettingsStore`.
nonisolated struct Settings: Equatable, Codable {
    var sidebarTitleCLI: CLIPreset
    var planCLI: CLIPreset
    var verifyCLI: CLIPreset
    var buildCLI: CLIPreset

    static let `default` = Settings(
        sidebarTitleCLI: .claude,
        planCLI: .claude,
        verifyCLI: .claude,
        buildCLI: .claude
    )

    /// Deduplicated list of skill directories across all configured CLI phases.
    var allSkillsDirectories: [URL] {
        var seen = Set<String>()
        return [sidebarTitleCLI, planCLI, verifyCLI, buildCLI]
            .compactMap(\.skillsDirectory)
            .filter { seen.insert($0.path).inserted }
    }
}

// MARK: - PerRepoSettings

/// Per-repo overrides stored in `{workingDirectory}/.aw/settings.json`.
/// A nil field means "not set; inherit from Global Settings."
/// Committed to git so teammates share the same per-repo configuration.
nonisolated struct PerRepoSettings: Equatable {
    var sidebarTitleCLI: CLIPreset?
    var planCLI: CLIPreset?
    var verifyCLI: CLIPreset?
    var buildCLI: CLIPreset?

    static let empty = PerRepoSettings()

    /// Returns `Settings` with each nil field falling back to the corresponding field in `base`.
    func merged(onto base: Settings) -> Settings {
        Settings(
            sidebarTitleCLI: sidebarTitleCLI ?? base.sidebarTitleCLI,
            planCLI: planCLI ?? base.planCLI,
            verifyCLI: verifyCLI ?? base.verifyCLI,
            buildCLI: buildCLI ?? base.buildCLI
        )
    }
}

nonisolated extension PerRepoSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case sidebarTitleCLI, planCLI, verifyCLI, buildCLI
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let v = sidebarTitleCLI { try container.encode(v, forKey: .sidebarTitleCLI) }
        if let v = planCLI { try container.encode(v, forKey: .planCLI) }
        if let v = verifyCLI { try container.encode(v, forKey: .verifyCLI) }
        if let v = buildCLI { try container.encode(v, forKey: .buildCLI) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sidebarTitleCLI = try container.decodeIfPresent(CLIPreset.self, forKey: .sidebarTitleCLI)
        planCLI = try container.decodeIfPresent(CLIPreset.self, forKey: .planCLI)
        verifyCLI = try container.decodeIfPresent(CLIPreset.self, forKey: .verifyCLI)
        buildCLI = try container.decodeIfPresent(CLIPreset.self, forKey: .buildCLI)
    }
}
