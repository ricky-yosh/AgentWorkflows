import SwiftUI

/// Center pane of the session detail layout.
/// Shows the most recently active terminal-capable engine and keeps the
/// default shell alive for sessions without a workflow.
struct TerminalHost: View {
    let session: Session

    @Environment(EngineManager.self) private var engineManager
    @Environment(SettingsStore.self) private var settingsStore
    @State private var hoveringRestart = false
    @State private var pendingToolSwitch: CLIPreset? = nil
    @State private var pendingEngineStart: DispatchWorkItem? = nil

    private var activeTerminalTool: String? {
        engineManager.activeTools(for: session.id).last
    }

    private var currentIdlePreset: CLIPreset {
        engineManager.idleToolOverride(for: session.id) ?? settingsStore.settings.buildCLI
    }

    private var idleTool: String {
        ProcessRunnerFactory.toolIdentifier(for: currentIdlePreset)
    }

    private var currentEngine: TerminalEngine? {
        if let activeTerminalTool {
            return engineManager.engine(for: session.id, tool: activeTerminalTool)
        }
        guard session.workflowName.isEmpty else { return nil }
        return engineManager.engine(for: session.id, tool: idleTool)
    }

    /// Agent display name for the terminal header, derived from the active or idle tool.
    private var agentDisplayName: String {
        let tool = activeTerminalTool ?? idleTool
        let parts = tool.split(separator: "/")
        return parts.count > 1 ? String(parts.last!).capitalized : tool.capitalized
    }

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            let engine = currentEngine
            ZStack {
                // TerminalViewWrapper is always present so its container NSView never
                // leaves the window hierarchy. Removing it would invalidate the
                // CAMetalLayer drawable and corrupt full-screen TUI apps (OpenCode).
                // When engine is nil we pass nil so the wrapper hides whatever was
                // showing but keeps it alive as a container subview.
                TerminalViewWrapper(terminalView: engine?.terminalView)
                    .overlay(alignment: .top) {
                        if session.workflowName.isEmpty,
                           case .terminated = engine?.engineState ?? .idle {
                            shellExitedBanner(for: engine!)
                                .padding()
                        }
                    }

                if engine == nil {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { startDefaultEngineIfNeeded() }
        .alert(
            "Switch to \(pendingToolSwitch?.displayName ?? "")?",
            isPresented: Binding(
                get: { pendingToolSwitch != nil },
                set: { if !$0 { pendingToolSwitch = nil } }
            )
        ) {
            Button("Switch", role: .destructive) {
                if let preset = pendingToolSwitch {
                    switchIdleTool(to: preset)
                }
                pendingToolSwitch = nil
            }
            Button("Cancel", role: .cancel) {
                pendingToolSwitch = nil
            }
        } message: {
            Text("The current terminal session will be terminated and its context will be lost.")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView(
            session.workflowName.isEmpty ? "Starting Shell" : "No Active Terminal",
            systemImage: session.workflowName.isEmpty ? "terminal" : "play.circle",
            description: Text(
                session.workflowName.isEmpty
                    ? "Launching the default shell for this session."
                    : "Run the workflow to open the terminal for the active CLI agent."
            )
        )
    }

    // MARK: - Header

    private var terminalHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            if engineManager.workflowEngine(for: session.id)?.activeLoopDriver != nil {
                Text("Terminal \u{2014} \(agentDisplayName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            } else {
                Menu {
                    ForEach(CLIPreset.allCases) { preset in
                        Button {
                            pendingToolSwitch = preset
                        } label: {
                            if preset == currentIdlePreset {
                                Label(preset.displayName, systemImage: "checkmark")
                            } else {
                                Text(preset.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("Terminal \u{2014} \(agentDisplayName)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Spacer()
            Button {
                restartEngine()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            .buttonStyle(.plain)
            .frame(width: 20, height: 20)
            .background(
                hoveringRestart
                    ? Color.white.opacity(0.08)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onHover { hoveringRestart = $0 }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(red: 0.176, green: 0.176, blue: 0.176))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private func switchIdleTool(to preset: CLIPreset) {
        guard preset != currentIdlePreset else { return }
        let oldTool = idleTool
        engineManager.setIdleToolOverride(preset, for: session.id)
        let newTool = idleTool
        engineManager.existingEngine(for: session.id, tool: oldTool)?.terminate()
        scheduleEngineStart(delay: 0.3) {
            let engine = engineManager.engine(for: session.id, tool: newTool)
            engineManager.promoteToLastTool(newTool, for: session.id)
            if case .terminated = engine.engineState { engine.terminate() }
            try? engine.start(workingDirectory: session.workingDirectory, tool: newTool)
        }
    }

    private func restartEngine() {
        let tool = activeTerminalTool ?? idleTool
        let engine = engineManager.engine(for: session.id, tool: tool)
        engine.terminate()
        scheduleEngineStart(delay: 0.5) {
            let restartedEngine = engineManager.engine(for: session.id, tool: tool)
            if case .terminated = restartedEngine.engineState { restartedEngine.terminate() }
            try? restartedEngine.start(workingDirectory: session.workingDirectory, tool: tool)
        }
    }

    private func scheduleEngineStart(delay: TimeInterval, work: @escaping () -> Void) {
        pendingEngineStart?.cancel()
        let item = DispatchWorkItem(block: work)
        pendingEngineStart = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Shell Banner

    private func shellExitedBanner(for engine: TerminalEngine) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Shell exited")
                .fontWeight(.medium)
            Spacer()
            Button("Restart Shell") {
                engine.terminate()
                startDefaultEngineIfNeeded()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func startDefaultEngineIfNeeded() {
        guard session.workflowName.isEmpty else { return }
        let tool = idleTool
        let engine = engineManager.engine(for: session.id, tool: tool)
        guard engine.engineState == .idle else { return }
        try? engine.start(workingDirectory: session.workingDirectory, tool: tool)
    }
}
