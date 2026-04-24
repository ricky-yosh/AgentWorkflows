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
            if let name = phaseName {
                Text(name)
                if name == "Build" {
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(status.tasksPassed)/\(status.tasksTotal)")
                }
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
