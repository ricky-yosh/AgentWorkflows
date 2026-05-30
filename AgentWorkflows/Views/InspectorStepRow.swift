import SwiftUI

enum InspectorStepStatus {
    case completed
    case current
    case pending

    var symbolName: String {
        switch self {
        case .completed:
            return "checkmark.circle.fill"
        case .current:
            return "circle.dotted"
        case .pending:
            return "circle"
        }
    }

    var color: Color {
        switch self {
        case .completed:
            return .green
        case .current:
            return .accentColor
        case .pending:
            return .secondary
        }
    }
}

/// Read-only step row for the workflow inspector.
/// Shows status + label and a run-from-here button only. No selection, no context menu, no agent badge.
struct InspectorStepRow: View {
    let step: WorkflowStep
    let status: InspectorStepStatus
    let onRunFromHere: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            StatusSymbolImage(symbolName: status.symbolName, color: status.color)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.displayName)
                    .font(.body)
                    .lineLimit(1)
                if let description = step.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Button(action: onRunFromHere) {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Run from here")
        }
        .padding(.vertical, 2)
    }
}
