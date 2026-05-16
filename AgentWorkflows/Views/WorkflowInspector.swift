import SwiftUI

private struct ContinueGateButtonStyle: ButtonStyle {
    var isHovered: Bool
    var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEnabled ? Color.accentColor : Color(nsColor: .controlColor))
            )
            .brightness(isHovered && isEnabled ? 0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

struct WorkflowInspector: View {
    let session: Session
    let workflow: Workflow?
    let workflowEngine: WorkflowEngine?
    @Binding var phaseExpansion: [AnyHashable: Bool]
    var onRunFromHere: ((Int, Int) -> Void)?

    @Environment(EngineManager.self) private var engineManager
    @State private var continueGateHovered = false

    var body: some View {
        VStack(spacing: 0) {
            if let workflow {
                phaseList(workflow: workflow)
            } else {
                Spacer()
                Text("No workflow selected")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }

            Divider()
            Button {
                engineManager.markStepComplete(sessionID: session.id)
            } label: {
                HStack(spacing: 6) {
                    Text("Mark step as complete")
                        .fontWeight(.semibold)
                    Text("⇧⌘↩")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(ContinueGateButtonStyle(isHovered: continueGateHovered, isEnabled: canMarkStepComplete))
            .controlSize(.large)
            .disabled(!canMarkStepComplete)
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .onHover { continueGateHovered = $0 }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .inspectorColumnWidth(min: 240, ideal: 320, max: 420)
        .onReceive(NotificationCenter.default.publisher(for: .awSessionMarkStepComplete)) { _ in
            engineManager.markStepComplete(sessionID: session.id)
        }
    }

    private var canMarkStepComplete: Bool {
        guard let we = engineManager.workflowEngine(for: session.id) else { return false }
        return we.executionState == .executing && we.activeLoopDriver == nil
    }

    private func phaseList(workflow: Workflow) -> some View {
        List {
            ForEach(Array(workflow.phases.enumerated()), id: \.element.id) { index, phase in
                let isExpanded = Binding<Bool>(
                    get: {
                        phaseExpansion[AnyHashable(phase.id)] ?? (index == displayPhaseIndex)
                    },
                    set: { phaseExpansion[AnyHashable(phase.id)] = $0 }
                )

                InspectorPhaseSection(
                    phase: phase,
                    workflow: workflow,
                    phaseIndex: index,
                    currentPhaseIndex: displayPhaseIndex,
                    currentStepIndex: displayStepIndex,
                    completedStepIDs: Set(displayCompletedStepIDs),
                    isExpanded: isExpanded,
                    onRunFromHere: { phaseIndex, stepIndex in
                        onRunFromHere?(phaseIndex, stepIndex)
                    }
                )
            }
        }
        .listStyle(.sidebar)
    }

    private var displayPhaseIndex: Int {
        workflowEngine?.currentPhaseIndex ?? session.currentPhaseIndex
    }

    private var displayStepIndex: Int {
        workflowEngine?.currentStepIndex ?? session.currentStepIndex
    }

    private var displayCompletedStepIDs: [String] {
        workflowEngine?.completedStepIDs ?? session.completedStepIDs
    }
}
