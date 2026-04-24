import SwiftUI

/// Read-only collapsible disclosure group per phase, containing inspector step rows.
struct InspectorPhaseSection: View {
    let phase: Phase
    let workflow: Workflow
    let phaseIndex: Int
    let currentPhaseIndex: Int
    let currentStepIndex: Int
    let completedStepIDs: Set<String>
    @Binding var isExpanded: Bool
    let onRunFromHere: (Int, Int) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(Array(phase.steps.enumerated()), id: \.element.id) { stepIndex, step in
                InspectorStepRow(
                    step: step,
                    status: status(for: step, at: stepIndex),
                    onRunFromHere: { onRunFromHere(phaseIndex, stepIndex) }
                )
                .padding(.leading, 8)
                .padding(.vertical, 1)
            }
        } label: {
            HStack(spacing: 6) {
                StatusSymbolImage(symbolName: phaseStatus.symbolName, color: phaseStatus.color)
                Text(phase.name)
                    .font(.subheadline)
                    .fontWeight(phaseIndex == currentPhaseIndex ? .semibold : .regular)
                    .foregroundStyle(phaseIndex == currentPhaseIndex ? .primary : .secondary)
                if phaseIndex == currentPhaseIndex {
                    Text("●")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .help("Active phase")
                }
            }
        }
    }

    private var phaseStatus: InspectorStepStatus {
        if phaseIndex < currentPhaseIndex { return .completed }
        if phaseIndex == currentPhaseIndex { return .current }
        return .pending
    }

    private func status(for step: WorkflowStep, at stepIndex: Int) -> InspectorStepStatus {
        if completedStepIDs.contains(step.id) { return .completed }
        if phaseIndex < currentPhaseIndex { return .completed }
        if phaseIndex == currentPhaseIndex {
            if stepIndex == currentStepIndex { return .current }
            if stepIndex < currentStepIndex { return .completed }
        }
        return .pending
    }
}
