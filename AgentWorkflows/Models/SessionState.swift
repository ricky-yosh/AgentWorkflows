import SwiftUI

nonisolated enum SessionState: String, Codable, Equatable, CaseIterable {
    case idle
    case running
    case paused
    case completed
    case stalled
}

extension SessionState {
    var symbolName: String {
        switch self {
        case .idle:
            return "circle"
        case .running:
            return "play.fill"
        case .paused:
            return "pause.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .stalled:
            return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .running:
            return .green
        case .paused:
            return .orange
        case .completed:
            return .green
        case .stalled:
            return .red
        }
    }

    var displayLabel: String {
        switch self {
        case .idle:
            return "idle"
        case .running:
            return "running"
        case .paused:
            return "paused"
        case .completed:
            return "completed"
        case .stalled:
            return "stalled"
        }
    }
}
