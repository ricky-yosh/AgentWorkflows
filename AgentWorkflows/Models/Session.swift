import Foundation

nonisolated struct SessionTransitionError: Error {
    let from: SessionState
    let to: SessionState
}

nonisolated struct Session: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var workingDirectory: String
    var workflowName: String
    var state: SessionState
    var currentPhaseIndex: Int
    var currentStepIndex: Int
    var completedStepIDs: [String]
    var manuallyTitled: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, workingDirectory, workflowName, state
        case currentPhaseIndex, currentStepIndex, completedStepIDs
        case manuallyTitled
    }

    init(id: UUID, name: String, workingDirectory: String, workflowName: String,
         state: SessionState, currentPhaseIndex: Int, currentStepIndex: Int,
         completedStepIDs: [String], manuallyTitled: Bool = false) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.workflowName = workflowName
        self.state = state
        self.currentPhaseIndex = currentPhaseIndex
        self.currentStepIndex = currentStepIndex
        self.completedStepIDs = completedStepIDs
        self.manuallyTitled = manuallyTitled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        workingDirectory = try c.decode(String.self, forKey: .workingDirectory)
        workflowName = try c.decode(String.self, forKey: .workflowName)
        state = try c.decode(SessionState.self, forKey: .state)
        currentPhaseIndex = try c.decode(Int.self, forKey: .currentPhaseIndex)
        currentStepIndex = try c.decode(Int.self, forKey: .currentStepIndex)
        completedStepIDs = try c.decode([String].self, forKey: .completedStepIDs)
        manuallyTitled = try c.decodeIfPresent(Bool.self, forKey: .manuallyTitled) ?? false
    }

    /// Validates and applies a state transition per R9.
    /// Valid: idle→running, running→paused, paused→running, running→idle, running→completed.
    mutating func transition(to newState: SessionState) throws {
        let valid: Bool
        switch (state, newState) {
        case (.idle, .running),
             (.running, .paused),
             (.paused, .running),
             (.running, .idle),
             (.running, .completed),
             (.running, .stalled),
             (.paused, .stalled),
             (.stalled, .idle),
             (.stalled, .running):
            valid = true
        default:
            valid = false
        }
        guard valid else {
            throw SessionTransitionError(from: state, to: newState)
        }
        state = newState
    }
}
