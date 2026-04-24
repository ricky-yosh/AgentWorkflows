import Foundation

/// Returns the current phase name for active sessions, nil otherwise.
nonisolated func currentPhaseName(session: Session, workflow: Workflow) -> String? {
    guard session.state == .running || session.state == .paused else { return nil }
    let index = session.currentPhaseIndex
    guard index >= 0 && index < workflow.phases.count else { return nil }
    return workflow.phases[index].name
}
