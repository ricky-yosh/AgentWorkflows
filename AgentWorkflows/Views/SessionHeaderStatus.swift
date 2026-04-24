import SwiftUI
import Combine

/// Sticky header above the Session main body. Shows state pip and label
/// at all times; adds phase name while running/paused; gates
/// iteration/task counters on the Build phase; hides elapsed until a run starts.
struct SessionHeaderStatus: View {
    @Bindable var status: SessionRunStatus
    let session: Session
    let workflow: Workflow?

    @State private var now: Date = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var phaseName: String? {
        guard let workflow else { return nil }
        return currentPhaseName(session: session, workflow: workflow)
    }

    private var isInBuildPhase: Bool {
        phaseName == "Build"
    }

    var body: some View {
        HStack(spacing: 12) {
            StatusBadgeView(sessionState: session.state)
            Text(session.state.displayLabel)
                .font(.caption.monospaced())
                .foregroundStyle(session.state.color)

            if let phaseName {
                Text("·").foregroundStyle(.tertiary)
                Text(phaseName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if isInBuildPhase {
                Text("·").foregroundStyle(.tertiary)
                Text("iteration \(status.iterationCount)/\(status.maxIterations)")
                    .font(.caption.monospaced())

                Text("·").foregroundStyle(.tertiary)

                Text("tasks \(status.tasksPassed)/\(status.tasksTotal)")
                    .font(.caption.monospaced())
            }

            if status.startedAt != nil {
                Text("·").foregroundStyle(.tertiary)
                Text("elapsed \(elapsedLabel)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .onReceive(tick) { now = $0 }
    }

    private var elapsedLabel: String {
        guard let seconds = status.elapsed(now: now) else { return "–" }
        return SessionRunStatus.formatElapsed(seconds)
    }
}
