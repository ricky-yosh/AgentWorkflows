import SwiftUI

struct PreferencesView: View {
    @AppStorage("maxIterations") private var maxIterations: Int = 25
    @AppStorage("diffViewerCommand") private var diffViewerCommand: String = DiffViewerLauncher.defaultCommand
    @AppStorage("editorCommand") private var editorCommand: String = EditorOption.xcode.shellCommand
    @AppStorage("terminalCommand") private var terminalCommand: String = TerminalOption.terminal.shellCommand
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        TabView {
            defaultsTab
                .tabItem { Label("Defaults", systemImage: "gearshape") }

            thisRepoTab
                .tabItem { Label("This Repo", systemImage: "folder") }
                .disabled(!settingsStore.hasActiveSession)

            generalTab
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }

            SkillsPreferencesPane()
                .tabItem { Label("Skills", systemImage: "puzzlepiece") }
        }
        .frame(width: 520, height: 420)
    }

    // MARK: - Defaults Tab

    private var defaultsTab: some View {
        Form {
            Section("Agent Presets") {
                sidebarTitleProviderRow("Sidebar Title", binding: sidebarTitleBinding)
                cliPresetRow("Plan CLI", binding: planCLIBinding)
                cliPresetRow("Verify CLI", binding: verifyCLIBinding)
                cliPresetRow("Build CLI", binding: buildCLIBinding)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func cliPresetRow(_ label: String, binding: Binding<CLIPreset>, codexEnabled: Bool = true) -> some View {
        LabeledContent(label) {
            Menu {
                Button("claude") { binding.wrappedValue = .claude }
                Divider()
                if codexEnabled {
                    Button("codex") { binding.wrappedValue = .codex }
                } else {
                    Button("codex") {}
                        .disabled(true)
                        .help("Codex title backend coming soon")
                }
                Button("pi") { binding.wrappedValue = .pi }
                Button("openCode") { binding.wrappedValue = .openCode }
            } label: {
                Text(binding.wrappedValue.rawValue.capitalized)
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private func sidebarTitleProviderRow(_ label: String, binding: Binding<SidebarTitleProvider>) -> some View {
        LabeledContent(label) {
            Menu {
                Button(SidebarTitleProvider.foundationModels.displayName) {
                    binding.wrappedValue = .foundationModels
                }
                Divider()
                Button(SidebarTitleProvider.claude.displayName) {
                    binding.wrappedValue = .claude
                }
                Button(SidebarTitleProvider.codex.displayName) {}
                    .disabled(true)
                    .help("Codex title backend coming soon")
                Button(SidebarTitleProvider.pi.displayName) {
                    binding.wrappedValue = .pi
                }
                Button(SidebarTitleProvider.openCode.displayName) {
                    binding.wrappedValue = .openCode
                }
            } label: {
                Text(binding.wrappedValue.displayName)
            }
            .fixedSize()
        }
    }

    // MARK: - Custom Bindings (Defaults)

    private var sidebarTitleBinding: Binding<SidebarTitleProvider> {
        Binding(
            get: { settingsStore.globalSettings.sidebarTitleProvider },
            set: { newValue in
                var updated = settingsStore.globalSettings
                updated.sidebarTitleProvider = newValue
                settingsStore.updateGlobal(updated)
            }
        )
    }

    private var planCLIBinding: Binding<CLIPreset> {
        Binding(
            get: { settingsStore.globalSettings.planCLI },
            set: { newValue in
                var updated = settingsStore.globalSettings
                updated.planCLI = newValue
                settingsStore.updateGlobal(updated)
            }
        )
    }

    private var verifyCLIBinding: Binding<CLIPreset> {
        Binding(
            get: { settingsStore.globalSettings.verifyCLI },
            set: { newValue in
                var updated = settingsStore.globalSettings
                updated.verifyCLI = newValue
                settingsStore.updateGlobal(updated)
            }
        )
    }

    private var buildCLIBinding: Binding<CLIPreset> {
        Binding(
            get: { settingsStore.globalSettings.buildCLI },
            set: { newValue in
                var updated = settingsStore.globalSettings
                updated.buildCLI = newValue
                settingsStore.updateGlobal(updated)
            }
        )
    }

    // MARK: - This Repo Tab

    private var thisRepoTab: some View {
        Form {
            Section("Agent Presets") {
                perRepoSidebarTitleProviderRow(
                    "Sidebar Title",
                    keyPath: \.sidebarTitleProvider,
                    globalValue: settingsStore.globalSettings.sidebarTitleProvider
                )
                perRepoCLIRow(
                    "Plan CLI",
                    keyPath: \.planCLI,
                    globalValue: settingsStore.globalSettings.planCLI
                )
                perRepoCLIRow(
                    "Verify CLI",
                    keyPath: \.verifyCLI,
                    globalValue: settingsStore.globalSettings.verifyCLI
                )
                perRepoCLIRow(
                    "Build CLI",
                    keyPath: \.buildCLI,
                    globalValue: settingsStore.globalSettings.buildCLI
                )
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func perRepoCLIRow(
        _ label: String,
        keyPath: WritableKeyPath<PerRepoSettings, CLIPreset?>,
        globalValue: CLIPreset,
        codexEnabled: Bool = true
    ) -> some View {
        let currentValue = settingsStore.perRepoSettings?[keyPath: keyPath]
        LabeledContent(label) {
            Menu {
                Button("Inherit from Defaults") {
                    var partial = settingsStore.perRepoSettings ?? .empty
                    partial[keyPath: keyPath] = nil
                    settingsStore.updatePerRepo(partial)
                }
                Divider()
                Button("claude") {
                    var partial = settingsStore.perRepoSettings ?? .empty
                    partial[keyPath: keyPath] = .claude
                    settingsStore.updatePerRepo(partial)
                }
                Divider()
                if codexEnabled {
                    Button("codex") {
                        var partial = settingsStore.perRepoSettings ?? .empty
                        partial[keyPath: keyPath] = .codex
                        settingsStore.updatePerRepo(partial)
                    }
                } else {
                    Button("codex") {}
                        .disabled(true)
                        .help("Codex title backend coming soon")
                }
                Button("pi") {
                    var partial = settingsStore.perRepoSettings ?? .empty
                    partial[keyPath: keyPath] = .pi
                    settingsStore.updatePerRepo(partial)
                }
                Button("openCode") {
                    var partial = settingsStore.perRepoSettings ?? .empty
                    partial[keyPath: keyPath] = .openCode
                    settingsStore.updatePerRepo(partial)
                }
            } label: {
                if let value = currentValue {
                    Text(value.rawValue)
                } else {
                    Text("\(globalValue.rawValue) (from Defaults)")
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private func perRepoSidebarTitleProviderRow(
        _ label: String,
        keyPath: WritableKeyPath<PerRepoSettings, SidebarTitleProvider?>,
        globalValue: SidebarTitleProvider
    ) -> some View {
        let currentValue = settingsStore.perRepoSettings?[keyPath: keyPath]
        LabeledContent(label) {
            Menu {
                Button("Inherit from Defaults") {
                    var partial = settingsStore.perRepoSettings ?? .empty
                    partial[keyPath: keyPath] = nil
                    settingsStore.updatePerRepo(partial)
                }
                Divider()
                Button(SidebarTitleProvider.foundationModels.displayName) {
                    var partial = settingsStore.perRepoSettings ?? .empty
                    partial[keyPath: keyPath] = .foundationModels
                    settingsStore.updatePerRepo(partial)
                }
                Divider()
                Button(SidebarTitleProvider.claude.displayName) {
                    var partial = settingsStore.perRepoSettings ?? .empty
                    partial[keyPath: keyPath] = .claude
                    settingsStore.updatePerRepo(partial)
                }
                Button(SidebarTitleProvider.codex.displayName) {}
                    .disabled(true)
                    .help("Codex title backend coming soon")
                Button(SidebarTitleProvider.pi.displayName) {
                    var partial = settingsStore.perRepoSettings ?? .empty
                    partial[keyPath: keyPath] = .pi
                    settingsStore.updatePerRepo(partial)
                }
                Button(SidebarTitleProvider.openCode.displayName) {
                    var partial = settingsStore.perRepoSettings ?? .empty
                    partial[keyPath: keyPath] = .openCode
                    settingsStore.updatePerRepo(partial)
                }
            } label: {
                if let value = currentValue {
                    Text(value.displayName)
                } else {
                    Text("\(globalValue.displayName) (from Defaults)")
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Loop") {
                Stepper(value: $maxIterations, in: 1...25) {
                    HStack {
                        Text("Max iterations")
                        Spacer()
                        Text("\(maxIterations)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text("Maximum number of Ralph iterations per Build Phase (1–25, default 25).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Editor") {
                EditorPreferenceView(editorCommand: $editorCommand)
            }

            Section("Terminal") {
                TerminalPreferenceView(terminalCommand: $terminalCommand)
            }

            Section("Diff Viewer") {
                DiffViewerPreferenceView(diffViewerCommand: $diffViewerCommand)
            }

            Section("Prerequisites") {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let report = PresenceChecker.check(
                    skillTargets: settingsStore.settings.allSkillTargets,
                    globalSettingsPath: home.appendingPathComponent(".claude/settings.json"),
                    projectSettingsPath: nil
                )
                let rows = PresenceBanner.missingRows(for: report)
                if rows.isEmpty {
                    Label("All prerequisites satisfied.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(rows, id: \.id) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).font(.body)
                            HStack(spacing: 8) {
                                Text(row.hint)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                if let link = row.link {
                                    Link("Docs", destination: link).font(.callout)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
