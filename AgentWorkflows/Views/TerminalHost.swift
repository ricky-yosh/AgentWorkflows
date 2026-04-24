import SwiftUI

/// Center pane of the session detail layout.
/// Shows the most recently active terminal-capable engine and keeps the
/// default shell alive for sessions without a workflow.
struct TerminalHost: View {
    let session: Session

    @Environment(EngineManager.self) private var engineManager

    private var activeTerminalTool: String? {
        engineManager.activeTools(for: session.id).last
    }

    private var currentEngine: TerminalEngine? {
        if let activeTerminalTool {
            return engineManager.engine(for: session.id, tool: activeTerminalTool)
        }
        guard session.workflowName.isEmpty else { return nil }
        return engineManager.engine(for: session.id, tool: engineManager.defaultAgent)
    }

    var body: some View {
        ZStack {
            if let engine = currentEngine {
                TerminalViewWrapper(terminalView: engine.terminalView)
                    .overlay(alignment: .top) {
                        if session.workflowName.isEmpty,
                           case .terminated = engine.engineState {
                            shellExitedBanner(for: engine)
                                .padding()
                        }
                    }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
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
        let tool = engineManager.defaultAgent
        let engine = engineManager.engine(for: session.id, tool: tool)
        guard engine.engineState == .idle else { return }
        try? engine.start(workingDirectory: session.workingDirectory, tool: tool)
    }
}
