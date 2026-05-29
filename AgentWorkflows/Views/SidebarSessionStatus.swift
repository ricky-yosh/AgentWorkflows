import SwiftUI
import Combine

/// Expanded status shown below the active session row in the sidebar.
/// Displays state badge, phase name, iteration/task counters (Build phase only),
/// and live elapsed time.
struct SidebarSessionStatus: View {
    @Bindable var status: SessionRunStatus
    let session: Session
    let workflow: Workflow?

    @State private var now: Date = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var phaseName: String? {
        guard let workflow else { return nil }
        return currentPhaseName(session: session, workflow: workflow)
    }

    var isInBuildPhase: Bool {
        phaseName == "Build"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                StatusBadgeView(sessionState: session.state)
                Text(session.state.displayLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(session.state.color)
            }

            if let phaseName {
                Text(phaseName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if isInBuildPhase {
                HStack(spacing: 4) {
                    Text("iter \(status.iterationCount)/\(status.maxIterations)")
                    Text("·").foregroundStyle(.tertiary)
                    Text("tasks \(status.tasksPassed)/\(status.tasksTotal)")
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            }

            if status.startedAt != nil {
                Text(elapsedLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(tick) { now = $0 }
    }

    private var elapsedLabel: String {
        guard let seconds = status.elapsed(now: now) else { return "–" }
        return SessionRunStatus.formatElapsed(seconds)
    }
}
