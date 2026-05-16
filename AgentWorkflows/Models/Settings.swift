import Foundation

// MARK: - SkillTarget

/// Destination where bundled skills are installed for a specific CLI ecosystem.
nonisolated enum SkillTarget: String, CaseIterable, Codable, Identifiable {
    case claude
    case codex
    case pi
    case openCode

    var id: String { rawValue }

    var directory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude:
            return home.appendingPathComponent(".claude/skills", isDirectory: true)
        case .codex:
            return home.appendingPathComponent(".codex/skills", isDirectory: true)
        case .pi:
            return home.appendingPathComponent(".agents/skills", isDirectory: true)
        case .openCode:
            return home.appendingPathComponent(".config/opencode/commands", isDirectory: true)
        }
    }
}

// MARK: - CLIPreset

/// The known AI CLI tools the app can invoke for subprocesses.
nonisolated enum CLIPreset: String, CaseIterable, Codable, Identifiable {
    case claude
    case codex
    case pi
    case openCode

    var id: String { rawValue }
    static let fallback: CLIPreset = .claude

    /// Everything needed to spawn a streaming subprocess for this CLI.
    struct InvocationRecipe {
        let binaryName: String
        let streamingFlags: [String]
        let terminalArgs: [String]

        init(binaryName: String, streamingFlags: [String] = [], terminalArgs: [String] = []) {
            self.binaryName = binaryName
            self.streamingFlags = streamingFlags
            self.terminalArgs = terminalArgs
        }
    }

    /// Returns the CLI recipe used by interactive terminal sessions and one-shot subprocesses.
    /// Headless build runners may still assemble their own argv when they need JSON output.
    var invocationRecipe: InvocationRecipe? {
        switch self {
        case .claude:
            return InvocationRecipe(
                binaryName: "claude",
                streamingFlags: [
                    "-p",
                    "--model", "sonnet",
                    "--output-format", "stream-json",
                    "--verbose"
                ],
                terminalArgs: []
            )
        case .codex:
            return InvocationRecipe(
                binaryName: "codex",
                terminalArgs: []
            )
        case .pi:
            return InvocationRecipe(binaryName: "pi")
        case .openCode:
            return InvocationRecipe(binaryName: "opencode")
        }
    }

    /// The directory where this CLI reads and writes skill files, or `nil` if the CLI has no skills concept.
    var skillsDirectory: URL? {
        skillTarget?.directory
    }

    var skillTarget: SkillTarget? {
        switch self {
        case .claude:
            return .claude
        case .codex:
            return .codex
        case .pi:
            return .pi
        case .openCode:
            return .openCode
        }
    }
}

nonisolated extension CLIPreset {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        self = CLIPreset(rawValue: rawValue) ?? .fallback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - SidebarTitleProvider

/// The backend used for one-shot sidebar session title generation.
nonisolated enum SidebarTitleProvider: String, CaseIterable, Codable, Identifiable {
    case foundationModels
    case claude
    case codex
    case pi
    case openCode

    var id: String { rawValue }
    static let fallback: SidebarTitleProvider = .claude

    var displayName: String {
        switch self {
        case .foundationModels:
            return "Apple Foundation Models"
        case .claude:
            return "Claude CLI"
        case .codex:
            return "Codex CLI"
        case .pi:
            return "Pi CLI"
        case .openCode:
            return "OpenCode CLI"
        }
    }

    var cliPreset: CLIPreset? {
        switch self {
        case .foundationModels:
            return nil
        case .claude:
            return .claude
        case .codex:
            return .codex
        case .pi:
            return .pi
        case .openCode:
            return .openCode
        }
    }

    static func cli(_ preset: CLIPreset) -> SidebarTitleProvider {
        switch preset {
        case .claude:
            return .claude
        case .codex:
            return .codex
        case .pi:
            return .pi
        case .openCode:
            return .openCode
        }
    }
}

nonisolated extension SidebarTitleProvider {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        self = SidebarTitleProvider(rawValue: rawValue) ?? .fallback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Settings

/// The effective configuration for the app — title generation plus one `CLIPreset` per subprocess call site.
/// Immutable value type; mutations go through `SettingsStore`.
nonisolated struct Settings: Equatable, Codable {
    var sidebarTitleProvider: SidebarTitleProvider
    var planCLI: CLIPreset
    var verifyCLI: CLIPreset
    var buildCLI: CLIPreset
    var excavationCLI: CLIPreset

    var sidebarTitleCLI: CLIPreset {
        get { sidebarTitleProvider.cliPreset ?? .claude }
        set { sidebarTitleProvider = .cli(newValue) }
    }

    init(
        sidebarTitleProvider: SidebarTitleProvider? = nil,
        sidebarTitleCLI: CLIPreset? = nil,
        planCLI: CLIPreset,
        verifyCLI: CLIPreset,
        buildCLI: CLIPreset,
        excavationCLI: CLIPreset? = nil
    ) {
        self.sidebarTitleProvider = sidebarTitleProvider ?? sidebarTitleCLI.map(SidebarTitleProvider.cli) ?? .claude
        self.planCLI = planCLI
        self.verifyCLI = verifyCLI
        self.buildCLI = buildCLI
        self.excavationCLI = excavationCLI ?? .claude
    }

    static let `default` = Settings(
        sidebarTitleProvider: .claude,
        planCLI: .claude,
        verifyCLI: .claude,
        buildCLI: .claude,
        excavationCLI: .claude
    )

    /// Deduplicated list of skill directories across all configured CLI phases.
    var allSkillsDirectories: [URL] {
        allSkillTargets.map(\.directory)
    }

    /// Deduplicated list of skill targets across all configured CLI phases.
    var allSkillTargets: [SkillTarget] {
        var seen = Set<String>()
        return [sidebarTitleProvider.cliPreset, planCLI, verifyCLI, buildCLI, excavationCLI]
            .compactMap { $0?.skillTarget }
            .filter { seen.insert($0.rawValue).inserted }
    }
}

nonisolated extension Settings {
    enum CodingKeys: String, CodingKey {
        case sidebarTitleProvider, sidebarTitleCLI, planCLI, verifyCLI, buildCLI, excavationCLI
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decodeIfPresent(SidebarTitleProvider.self, forKey: .sidebarTitleProvider)
        let legacyCLI = try container.decodeIfPresent(CLIPreset.self, forKey: .sidebarTitleCLI)
        self.init(
            sidebarTitleProvider: provider,
            sidebarTitleCLI: legacyCLI,
            planCLI: try container.decode(CLIPreset.self, forKey: .planCLI),
            verifyCLI: try container.decode(CLIPreset.self, forKey: .verifyCLI),
            buildCLI: try container.decode(CLIPreset.self, forKey: .buildCLI),
            excavationCLI: try container.decodeIfPresent(CLIPreset.self, forKey: .excavationCLI)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sidebarTitleProvider, forKey: .sidebarTitleProvider)
        try container.encode(planCLI, forKey: .planCLI)
        try container.encode(verifyCLI, forKey: .verifyCLI)
        try container.encode(buildCLI, forKey: .buildCLI)
        try container.encode(excavationCLI, forKey: .excavationCLI)
    }
}

// MARK: - PerRepoSettings

/// Per-repo overrides stored in `{workingDirectory}/.aw/settings.json`.
/// A nil field means "not set; inherit from Global Settings."
/// Committed to git so teammates share the same per-repo configuration.
nonisolated struct PerRepoSettings: Equatable {
    var sidebarTitleProvider: SidebarTitleProvider?
    var planCLI: CLIPreset?
    var verifyCLI: CLIPreset?
    var buildCLI: CLIPreset?
    var excavationCLI: CLIPreset?

    var sidebarTitleCLI: CLIPreset? {
        get { sidebarTitleProvider?.cliPreset }
        set { sidebarTitleProvider = newValue.map(SidebarTitleProvider.cli) }
    }

    init(
        sidebarTitleProvider: SidebarTitleProvider? = nil,
        sidebarTitleCLI: CLIPreset? = nil,
        planCLI: CLIPreset? = nil,
        verifyCLI: CLIPreset? = nil,
        buildCLI: CLIPreset? = nil,
        excavationCLI: CLIPreset? = nil
    ) {
        self.sidebarTitleProvider = sidebarTitleProvider ?? sidebarTitleCLI.map(SidebarTitleProvider.cli)
        self.planCLI = planCLI
        self.verifyCLI = verifyCLI
        self.buildCLI = buildCLI
        self.excavationCLI = excavationCLI
    }

    static let empty = PerRepoSettings()

    /// Returns `Settings` with each nil field falling back to the corresponding field in `base`.
    func merged(onto base: Settings) -> Settings {
        Settings(
            sidebarTitleProvider: sidebarTitleProvider ?? base.sidebarTitleProvider,
            planCLI: planCLI ?? base.planCLI,
            verifyCLI: verifyCLI ?? base.verifyCLI,
            buildCLI: buildCLI ?? base.buildCLI,
            excavationCLI: excavationCLI ?? base.excavationCLI
        )
    }
}

nonisolated extension PerRepoSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case sidebarTitleProvider, sidebarTitleCLI, planCLI, verifyCLI, buildCLI, excavationCLI
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let v = sidebarTitleProvider { try container.encode(v, forKey: .sidebarTitleProvider) }
        if let v = planCLI { try container.encode(v, forKey: .planCLI) }
        if let v = verifyCLI { try container.encode(v, forKey: .verifyCLI) }
        if let v = buildCLI { try container.encode(v, forKey: .buildCLI) }
        if let v = excavationCLI { try container.encode(v, forKey: .excavationCLI) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decodeIfPresent(SidebarTitleProvider.self, forKey: .sidebarTitleProvider)
        let legacyCLI = try container.decodeIfPresent(CLIPreset.self, forKey: .sidebarTitleCLI)
        sidebarTitleProvider = provider ?? legacyCLI.map(SidebarTitleProvider.cli)
        planCLI = try container.decodeIfPresent(CLIPreset.self, forKey: .planCLI)
        verifyCLI = try container.decodeIfPresent(CLIPreset.self, forKey: .verifyCLI)
        buildCLI = try container.decodeIfPresent(CLIPreset.self, forKey: .buildCLI)
        excavationCLI = try container.decodeIfPresent(CLIPreset.self, forKey: .excavationCLI)
    }
}
