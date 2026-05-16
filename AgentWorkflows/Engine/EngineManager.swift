import Foundation
import AppKit
import Observation

@Observable
final class EngineManager {
    /// Terminal engines keyed by session ID, then by tool name (e.g. "cli/zsh").
    private var engines: [UUID: [String: TerminalEngine]] = [:]
    /// Insertion-ordered tool names per session, for stable tab ordering.
    private var toolOrder: [UUID: [String]] = [:]
    private var workflowEngines: [UUID: WorkflowEngine] = [:]
    private var runStatuses: [UUID: SessionRunStatus] = [:]
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.terminateAll()
        }
    }

    deinit {
        if let obs = terminationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// Live status surface for a Session — backs SessionHeaderStatus and
    /// SessionCardStatus. Lazily created on first read so every Session has
    /// a stable status object regardless of whether the run has started.
    @MainActor
    func runStatus(for sessionID: UUID) -> SessionRunStatus {
        if let existing = runStatuses[sessionID] { return existing }
        let status = SessionRunStatus(
            maxIterations: UserDefaults.standard.object(forKey: "maxIterations") as? Int ?? 25
        )
        runStatuses[sessionID] = status
        return status
    }

    /// The default agent preference. Ralph is the only workflow, so claude is
    /// the only agent it makes sense to default to. UserDefaults can still
    /// override via the `defaultAgent` key for manual testing, but only values
    /// that resolve to a known `CLIPreset` with an `invocationRecipe` are honored —
    /// stale values from retired presets (e.g. `"cli/claude-safe"` from an earlier
    /// build) would otherwise make `ensureTerminalRunning` spawn a bare login shell
    /// while the WorkflowEngine resolver creates a separate, invisible engine for
    /// the real preset.
    var defaultAgent: String {
        let stored = UserDefaults.standard.string(forKey: "defaultAgent") ?? "cli/claude"
        if stored.hasPrefix("cli/"),
           let preset = CLIPreset(rawValue: String(stored.dropFirst(4))),
           preset.invocationRecipe != nil {
            return stored
        }
        return "cli/claude"
    }

    /// Maps tool identifiers of the form `"cli/<preset>"` to their CLI invocation
    /// by looking up the binary name from `CLIPreset.invocationRecipe`. Returns nil
    /// for unrecognised identifiers (e.g. `"cli/zsh"`), letting TerminalEngine fall
    /// back to its default login shell.
    static func toolDefinition(for tool: String) -> CLIToolDefinition? {
        guard tool.hasPrefix("cli/") else { return nil }
        let presetName = String(tool.dropFirst(4))
        guard let preset = CLIPreset(rawValue: presetName),
              let recipe = preset.invocationRecipe else { return nil }
        return CLIToolDefinition(name: recipe.binaryName, command: recipe.binaryName, defaultArgs: recipe.terminalArgs)
    }

    /// Returns (or creates) the engine for a session + tool pair.
    /// Pass `nil` for tool to use the user's default agent preference.
    func engine(for sessionID: UUID, tool: String? = nil) -> TerminalEngine {
        let tool = tool ?? defaultAgent
        if let existing = engines[sessionID]?[tool] { return existing }
        let engine = TerminalEngine()
        engine.toolDefinition = Self.toolDefinition(for: tool)
        engines[sessionID, default: [:]][tool] = engine
        if toolOrder[sessionID] == nil {
            toolOrder[sessionID] = [tool]
        } else if toolOrder[sessionID]?.contains(tool) == false {
            toolOrder[sessionID]?.append(tool)
        }
        return engine
    }

    /// Returns tool names with active engines for a session, in creation order.
    func activeTools(for sessionID: UUID) -> [String] {
        toolOrder[sessionID] ?? []
    }

    func existingEngine(for sessionID: UUID, tool: String) -> TerminalEngine? {
        engines[sessionID]?[tool]
    }

    func workflowEngine(for sessionID: UUID) -> WorkflowEngine? {
        workflowEngines[sessionID]
    }

    @MainActor
    func createWorkflowEngine(
        session: Session,
        workflow: Workflow,
        settingsStore: SettingsStore? = nil,
        seedIntent: String? = nil
    ) -> WorkflowEngine {
        workflowEngines[session.id]?.stop()

        let signalPath = Self.signalFilePath(for: session)
        let we = WorkflowEngine(
            session: session,
            workflow: workflow,
            engineResolver: { [weak self] agent in
                guard let self else { return TerminalEngine() }
                let tool = (agent?.isEmpty == false ? agent! : self.defaultAgent)
                let engine = self.engine(for: session.id, tool: tool)
                if engine.engineState != .running {
                    if case .terminated = engine.engineState {
                        engine.terminate()  // reset to idle so start() can re-launch
                    }
                    try? engine.start(workingDirectory: session.workingDirectory, tool: tool)
                }
                if engine.templateResolver == nil {
                    engine.templateResolver = TemplateResolver(sessionID: session.id)
                }
                return engine
            },
            signalFilePath: signalPath,
            settingsStore: settingsStore
        )
        if let seedIntent { we.seedNextPrompt(seedIntent) }
        we.sessionRunStatus = runStatus(for: session.id)
        workflowEngines[session.id] = we
        return we
    }

    func configureResolver(for session: Session) {
        let resolver = TemplateResolver(sessionID: session.id)
        if let sessionEngines = engines[session.id] {
            for (_, engine) in sessionEngines {
                engine.templateResolver = resolver
            }
        }
    }

    /// Kills all in-flight subprocesses immediately — called on app quit so no
    /// orphan `claude -p` processes remain after the dispatch queues drain.
    func terminateAll() {
        for sessionID in Array(workflowEngines.keys) {
            workflowEngines[sessionID]?.forceStop()
            engines[sessionID]?.values.forEach { $0.terminate() }
        }
    }

    /// Marks the current prompt step complete and advances the workflow.
    /// No-op when no workflow engine is executing a prompt step.
    func markStepComplete(sessionID: UUID) {
        workflowEngines[sessionID]?.handleStepCompletion()
    }

    func removeEngine(for sessionID: UUID) {
        workflowEngines[sessionID]?.stop()
        workflowEngines[sessionID] = nil
        engines[sessionID]?.values.forEach { $0.terminate() }
        engines[sessionID] = nil
        toolOrder[sessionID] = nil
    }

    private static func signalFilePath(for session: Session) -> String {
        SessionDirectoryLayout.signalFileURL(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: session.id
        ).path
    }
}
