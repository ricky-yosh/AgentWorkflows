import SwiftUI

/// Compact status line rendered inside each Session row in the sidebar.
/// Shows only the state pip when idle/completed/stalled, adds phase name when active,
/// and adds tasks X/Y when in the Build phase.
struct SessionCardStatus: View {
    @Bindable var status: SessionRunStatus
    let session: Session
    let workflow: Workflow

    private var phaseName: String? {
        currentPhaseName(session: session, workflow: workflow)
    }

    var body: some View {
        HStack(spacing: 4) {
            StatusBadgeView(sessionState: session.state)
            if let modelLabel = status.sidebarModelLabel {
                Text(modelLabel)
                    .lineLimit(1)
            }
            if let name = phaseName {
                if status.sidebarModelLabel != nil {
                    Text("·").foregroundStyle(.tertiary)
                }
                Text(name)
                if name == "Build" {
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(status.tasksPassed)/\(status.tasksTotal)")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
