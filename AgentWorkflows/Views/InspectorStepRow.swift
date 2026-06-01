import SwiftUI

enum InspectorStepStatus {
    case completed
    case current
    case pending

    var symbolName: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .current:   return "circle.dotted"
        case .pending:   return "circle"
        }
    }

    var color: Color {
        switch self {
        case .completed: return .green
        case .current:   return .accentColor
        case .pending:   return .secondary
        }
    }
}

/// Read-only step row for the workflow inspector.
struct InspectorStepRow: View {
    let step: WorkflowStep
    let status: InspectorStepStatus
    let executionState: ExecutionState
    let onRunFromHere: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            statusIndicator
                .frame(width: 16, height: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(status == .completed, color: .secondary)
                    .lineLimit(1)
                if let description = step.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                statusCaption
            }

            Spacer(minLength: 4)

            // Reveal on hover only — avoids visual noise on static rows
            Button(action: onRunFromHere) {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1.0 : 0.0)
            .help("Run from here")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(status == .current ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    status == .current ? Color.accentColor.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Run from This Step", action: onRunFromHere)
            Divider()
            Button("Copy Step Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(step.displayName, forType: .string)
            }
            if let desc = step.description, !desc.isEmpty {
                Button("Copy Description") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(desc, forType: .string)
                }
            }
        }
    }

    // MARK: - Status indicator

    @ViewBuilder
    private var statusIndicator: some View {
        if status == .current {
            switch executionState {
            case .executing:
                ProgressView()
                    .controlSize(.mini)
            case .paused:
                Image(systemName: "pause.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            case .stalled:
                Image(systemName: "exclamationmark.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
            default:
                // idle or completed workflow — cursor is parked here but nothing is running
                Image(systemName: "circle.dotted")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
        } else {
            StatusSymbolImage(symbolName: status.symbolName, color: status.color)
        }
    }

    // MARK: - Inline status caption

    @ViewBuilder
    private var statusCaption: some View {
        if status == .current {
            switch executionState {
            case .executing:
                Text("Agent is working…")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            case .paused:
                Text("Paused — waiting for input")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            case .stalled:
                Text("Stalled")
                    .font(.caption)
                    .foregroundStyle(.orange)
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Preview

#Preview("Step Rows — All States") {
    let base = WorkflowStep(id: "s", type: .prompt, label: "Write PRD",
                            agent: nil, prompt: "/to-prd", promptFile: nil,
                            description: "Generate PRD from conversation")
    let noDesc = WorkflowStep(id: "s2", type: .prompt, label: "Grill with Docs",
                              agent: nil, prompt: "/grill", promptFile: nil,
                              description: nil)

    VStack(alignment: .leading, spacing: 0) {
        Group {
            Text("Completed").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 8)
            InspectorStepRow(step: noDesc, status: .completed, executionState: .idle, onRunFromHere: {})
                .padding(.horizontal, 12)
            Divider().padding(.leading, 38)

            Text("Current · Executing").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 8)
            InspectorStepRow(step: base, status: .current, executionState: .executing, onRunFromHere: {})
                .padding(.horizontal, 12)
            Divider().padding(.leading, 38)

            Text("Current · Paused").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 8)
            InspectorStepRow(step: base, status: .current, executionState: .paused, onRunFromHere: {})
                .padding(.horizontal, 12)
            Divider().padding(.leading, 38)

            Text("Current · Stalled").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 8)
            InspectorStepRow(step: base, status: .current, executionState: .stalled, onRunFromHere: {})
                .padding(.horizontal, 12)
            Divider().padding(.leading, 38)

            Text("Pending").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 8)
            InspectorStepRow(step: base, status: .pending, executionState: .idle, onRunFromHere: {})
                .padding(.horizontal, 12)
        }
    }
    .padding(.vertical, 4)
}
