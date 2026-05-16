import AppKit
import SwiftUI

struct ExcavationChatView: View {
    let session: Session
    @Binding var isPresented: Bool

    @Environment(EngineManager.self) private var engineManager
    @Environment(SettingsStore.self) private var settingsStore

    private var excavationTool: String {
        ProcessRunnerFactory.toolIdentifier(for: settingsStore.settings.excavationCLI)
    }

    private var excavationEngine: TerminalEngine {
        engineManager.engine(for: session.id, role: .excavation, tool: excavationTool)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isPresented ? "chevron.down" : "chevron.up")
                    Text("Excavation")
                        .font(.headline)
                    Spacer()
                    Text(settingsStore.settings.excavationCLI.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isPresented {
                Divider()
                content
                    .frame(minHeight: 220, maxHeight: 280)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task(id: session.state) {
            startExcavationEngineIfNeeded()
        }
        .onAppear {
            startExcavationEngineIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.state == .idle {
            ContentUnavailableView(
                "Excavation Ready",
                systemImage: "sparkles",
                description: Text("The excavation terminal opens when the session starts.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TerminalViewWrapper(terminalView: excavationEngine.terminalView)
                .overlay(alignment: .top) {
                    if case .terminated = excavationEngine.engineState {
                        shellExitedBanner
                            .padding()
                    }
                }
        }
    }

    private var shellExitedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Excavation shell exited")
                .fontWeight(.medium)
            Spacer()
            Button("Restart") {
                excavationEngine.terminate()
                startExcavationEngineIfNeeded()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func startExcavationEngineIfNeeded() {
        guard session.state != .idle else { return }
        engineManager.configureResolver(for: session)
        guard excavationEngine.engineState != .running else { return }
        try? excavationEngine.start(
            workingDirectory: session.workingDirectory,
            tool: excavationTool
        )
    }
}
