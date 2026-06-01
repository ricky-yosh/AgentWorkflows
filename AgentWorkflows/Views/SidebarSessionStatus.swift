import SwiftUI

/// Expanded status shown below the active session row in the sidebar.
/// Displays state badge, phase name, iteration/task counters (Build phase only),
/// and live elapsed time.
struct SidebarSessionStatus: View {
    @Bindable var status: SessionRunStatus
    let session: Session
    let workflow: Workflow?

    @State private var now: Date = Date()

    var phaseName: String? {
        guard let workflow else { return nil }
        return currentPhaseName(session: session, workflow: workflow)
    }

    var isInBuildPhase: Bool {
        phaseName == "Build"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                StatusBadgeView(sessionState: session.state)
                Text(session.state.displayLabel)
                    .foregroundStyle(session.state.color)
                if let phaseName {
                    Text("·").foregroundStyle(.tertiary)
                    Text(phaseName)
                } else if let modelLabel = status.sidebarModelLabel {
                    Text("·").foregroundStyle(.tertiary)
                    Text(modelLabel).lineLimit(1)
                }
                if status.startedAt != nil {
                    Spacer()
                    Text(elapsedLabel)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if isInBuildPhase {
                HStack(spacing: 4) {
                    Text("iter \(status.iterationCount)/\(status.maxIterations)")
                    Text("·").foregroundStyle(.tertiary)
                    Text("tasks \(status.tasksPassed)/\(status.tasksTotal)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
    }

    private var elapsedLabel: String {
        guard let seconds = status.elapsed(now: now) else { return "–" }
        return SessionRunStatus.formatElapsed(seconds)
    }
}
