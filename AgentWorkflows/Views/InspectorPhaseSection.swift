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
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
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
                    Text(stepCountLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(phaseStatusBadgeText)
                    .font(.system(size: 10))
                    .fontWeight(.medium)
                    .foregroundStyle(phaseStatusBadgeColors.fg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(phaseStatusBadgeColors.bg, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var stepCountLabel: String {
        let completedInPhase = phase.steps.filter { completedStepIDs.contains($0.id) }.count
        let totalInPhase = phase.steps.count
        if completedInPhase == totalInPhase {
            return "\(completedInPhase) of \(totalInPhase) steps completed"
        } else {
            return "\(completedInPhase) of \(totalInPhase) steps"
        }
    }

    private var phaseStatusBadgeText: String {
        if phaseIndex < currentPhaseIndex { return "Completed" }
        if phaseIndex == currentPhaseIndex { return "Current" }
        return "Pending"
    }

    private var phaseStatusBadgeColors: (bg: Color, fg: Color) {
        if phaseIndex < currentPhaseIndex {
            return (Color(hex: "#e8f5e9"), Color(hex: "#2e7d32"))
        }
        if phaseIndex == currentPhaseIndex {
            return (Color(hex: "#e3f2fd"), Color(hex: "#1565c0"))
        }
        return (Color(hex: "#f5f5f5"), Color(hex: "#757575"))
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
