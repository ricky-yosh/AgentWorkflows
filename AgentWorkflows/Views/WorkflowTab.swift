import SwiftUI

struct WorkflowTab: View {
    let session: Session
    let workflow: Workflow?
    let workflowEngine: WorkflowEngine?
    @Binding var phaseExpansion: [AnyHashable: Bool]
    var onRunFromHere: ((Int, Int) -> Void)?

    @Environment(EngineManager.self) private var engineManager
    @State private var continueGateHovered = false

    var body: some View {
        VStack(spacing: 0) {
            workflowHeader

            if let workflow {
                WorkflowPhaseList(
                    phases: workflow.phases,
                    workflow: workflow,
                    currentPhaseIndex: displayPhaseIndex,
                    currentStepIndex: displayStepIndex,
                    completedStepIDs: Set(displayCompletedStepIDs),
                    executionState: workflowEngine?.executionState ?? .idle,
                    phaseExpansion: $phaseExpansion,
                    onRunFromHere: { phaseIndex, stepIndex in
                        onRunFromHere?(phaseIndex, stepIndex)
                    }
                )
            } else {
                emptyState
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            continueGateFooter
        }
        .onReceive(NotificationCenter.default.publisher(for: .awSessionMarkStepComplete)) { _ in
            engineManager.markStepComplete(sessionID: session.id)
        }
    }

    // MARK: - Subviews

    private var workflowHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Workflow Progress")
                .font(.system(size: 14, weight: .semibold))
            Text(session.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var emptyState: some View {
        Spacer()
        Text("No workflow selected")
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
        Spacer()
    }

    private var continueGateFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                engineManager.markStepComplete(sessionID: session.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .symbolEffect(.bounce, value: canMarkStepComplete)
                    Text("Mark step as complete")
                        .fontWeight(.semibold)
                    Text("\u{21E7}\u{2318}\u{21A9}")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .padding(.vertical, 1)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.15))
                        )
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
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private var canMarkStepComplete: Bool {
        guard let we = engineManager.workflowEngine(for: session.id) else { return false }
        return we.executionState == .executing && we.activeLoopDriver == nil
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

// MARK: - WorkflowPhaseList

/// Pure-value scroll container for the phase list. No @Environment — previewable
/// with plain data. WorkflowTab maps engine state into these parameters.
struct WorkflowPhaseList: View {
    let phases: [Phase]
    let workflow: Workflow
    let currentPhaseIndex: Int
    let currentStepIndex: Int
    let completedStepIDs: Set<String>
    let executionState: ExecutionState
    @Binding var phaseExpansion: [AnyHashable: Bool]
    let onRunFromHere: (Int, Int) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(phases.enumerated()), id: \.element.id) { index, phase in
                    let isExpanded = Binding<Bool>(
                        get: { phaseExpansion[AnyHashable(phase.id)] ?? (index == currentPhaseIndex) },
                        set: { phaseExpansion[AnyHashable(phase.id)] = $0 }
                    )
                    InspectorPhaseSection(
                        phase: phase,
                        workflow: workflow,
                        phaseIndex: index,
                        currentPhaseIndex: currentPhaseIndex,
                        currentStepIndex: currentStepIndex,
                        completedStepIDs: completedStepIDs,
                        executionState: executionState,
                        isExpanded: isExpanded,
                        onRunFromHere: { phaseIndex, stepIndex in
                            onRunFromHere(phaseIndex, stepIndex)
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - ContinueGateButtonStyle

private struct ContinueGateButtonStyle: ButtonStyle {
    var isHovered: Bool
    var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor)
            )
            .opacity(isEnabled ? 1.0 : 0.4)
            .brightness(isHovered && isEnabled ? 0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Preview

#Preview("Workflow Phase List") {
    @Previewable @State var phaseExpansion: [AnyHashable: Bool] = [:]

    let workflow = Workflow.ralph
    let completedIDs: Set<String> = ["plan-grill-with-docs", "plan-to-prd", "plan-to-tasks"]

    WorkflowPhaseList(
        phases: workflow.phases,
        workflow: workflow,
        currentPhaseIndex: 1,
        currentStepIndex: 0,
        completedStepIDs: completedIDs,
        executionState: .executing,
        phaseExpansion: $phaseExpansion,
        onRunFromHere: { _, _ in }
    )
    .frame(width: 380, height: 500)
}
