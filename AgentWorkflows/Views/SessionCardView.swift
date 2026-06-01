import SwiftUI

struct SessionCardView: View {
    let session: Session
    @Environment(EngineManager.self) private var engineManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.name)
                .font(.body)
                .lineLimit(1)
            SessionCardStatus(
                status: engineManager.runStatus(for: session.id),
                session: session,
                workflow: .ralph
            )
        }
        .onAppear { primeTaskCounts() }
    }

    private func primeTaskCounts() {
        let dir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: session.id
        )
        let passes = WorkflowEngine.readPasses(progressDir: dir.path)
        guard !passes.isEmpty else { return }
        let status = engineManager.runStatus(for: session.id)
        status.tasksPassed = passes.filter { $0 }.count
        status.tasksTotal = passes.count
    }
}
