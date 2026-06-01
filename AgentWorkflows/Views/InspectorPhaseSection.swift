import SwiftUI

struct InspectorPhaseSection: View {
    let phase: Phase
    let workflow: Workflow
    let phaseIndex: Int
    let currentPhaseIndex: Int
    let currentStepIndex: Int
    let completedStepIDs: Set<String>
    let executionState: ExecutionState
    @Binding var isExpanded: Bool
    let onRunFromHere: (Int, Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // 3pt color track — replaces the text badge as the primary status signal
            phaseStatus.color
                .frame(width: 3)

            VStack(spacing: 0) {
                headerRow
                progressTrack

                if isExpanded, !phase.steps.isEmpty {
                    Divider()
                    stepsView
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Group {
                if !phase.steps.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isExpanded)
                } else {
                    Color.clear
                }
            }
            .frame(width: 12, height: 12)

            Text(phase.name)
                .font(.callout)
                .fontWeight(phaseIndex == currentPhaseIndex ? .semibold : .regular)
                .foregroundStyle(phaseIndex == currentPhaseIndex ? .primary : .secondary)

            Spacer()

            Text(stepCountLabel)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !phase.steps.isEmpty else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Progress Track

    private var progressTrack: some View {
        Rectangle()
            .fill(Color(NSColor.quaternaryLabelColor).opacity(0.3))
            .frame(height: 2)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(phaseStatus.color)
                        .frame(width: geo.size.width * completedFraction)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: completedFraction)
                }
            }
            .clipShape(Capsule())
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    // MARK: - Steps

    private var stepsView: some View {
        VStack(spacing: 0) {
            ForEach(Array(phase.steps.enumerated()), id: \.element.id) { stepIndex, step in
                InspectorStepRow(
                    step: step,
                    status: status(for: step, at: stepIndex),
                    executionState: executionState,
                    onRunFromHere: { onRunFromHere(phaseIndex, stepIndex) }
                )
                .padding(.horizontal, 12)

                if stepIndex < phase.steps.count - 1 {
                    Divider()
                        .padding(.leading, 38) // aligns with step name text
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var stepCountLabel: String {
        let done = phase.steps.filter { completedStepIDs.contains($0.id) }.count
        return "\(done)/\(phase.steps.count)"
    }

    private var completedFraction: Double {
        guard !phase.steps.isEmpty else { return 0 }
        let done = phase.steps.filter { completedStepIDs.contains($0.id) }.count
        return Double(done) / Double(phase.steps.count)
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

// MARK: - Preview

#Preview("Phase Sections") {
    @Previewable @State var planExpanded = true
    @Previewable @State var buildExpanded = true

    let workflow = Workflow.ralph
    let completedIDs: Set<String> = ["plan-grill-with-docs", "plan-to-prd", "plan-to-tasks"]

    ScrollView {
        LazyVStack(spacing: 12) {
            InspectorPhaseSection(
                phase: workflow.phases[0],
                workflow: workflow,
                phaseIndex: 0,
                currentPhaseIndex: 1,
                currentStepIndex: 0,
                completedStepIDs: completedIDs,
                executionState: .executing,
                isExpanded: $planExpanded,
                onRunFromHere: { _, _ in }
            )
            InspectorPhaseSection(
                phase: workflow.phases[1],
                workflow: workflow,
                phaseIndex: 1,
                currentPhaseIndex: 1,
                currentStepIndex: 0,
                completedStepIDs: completedIDs,
                executionState: .executing,
                isExpanded: $buildExpanded,
                onRunFromHere: { _, _ in }
            )
            InspectorPhaseSection(
                phase: workflow.phases[2],
                workflow: workflow,
                phaseIndex: 2,
                currentPhaseIndex: 1,
                currentStepIndex: 0,
                completedStepIDs: completedIDs,
                executionState: .idle,
                isExpanded: .constant(false),
                onRunFromHere: { _, _ in }
            )
        }
        .padding()
    }
}
