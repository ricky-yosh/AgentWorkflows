import SwiftUI

/// Center pane of the session detail layout.
/// Shows the most recently active terminal-capable engine and keeps the
/// default shell alive for sessions without a workflow.
struct TerminalHost: View {
    let session: Session

    @Environment(EngineManager.self) private var engineManager
    @Environment(SettingsStore.self) private var settingsStore
    @State private var hoveringRestart = false

    private var activeTerminalTool: String? {
        engineManager.activeTools(for: session.id).last
    }

    private var idleTool: String {
        ProcessRunnerFactory.toolIdentifier(for: settingsStore.settings.buildCLI)
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
                .foregroundColor(Color(red: 0.533, green: 0.533, blue: 0.533))
            Text("Terminal \u{2014} \(agentDisplayName)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
            Spacer()
            Button {
                restartEngine()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
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

    private func restartEngine() {
        let tool = activeTerminalTool ?? idleTool
        let engine = engineManager.engine(for: session.id, tool: tool)
        engine.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let restartedEngine = engineManager.engine(for: session.id, tool: tool)
            try? restartedEngine.start(workingDirectory: session.workingDirectory, tool: tool)
        }
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
