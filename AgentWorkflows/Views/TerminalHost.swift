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
        let engine = currentEngine
        let _ = print("[TH] body — session=\(session.id.uuidString.prefix(8)) activeTool=\(activeTerminalTool ?? "nil") engine=\(engine == nil ? "nil" : "present")")
        ZStack {
            // TerminalViewWrapper is always present so its container NSView never
            // leaves the window hierarchy. Removing it would invalidate the
            // CAMetalLayer drawable and corrupt full-screen TUI apps (OpenCode).
            // When engine is nil we pass nil so the wrapper hides whatever was
            // showing but keeps it alive as a container subview.
            let _ = print("[TH] rendering TerminalViewWrapper — terminalView=\(engine.map { "\(ObjectIdentifier($0.terminalView))" } ?? "nil")")
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
