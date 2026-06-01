import SwiftUI

struct StatusBadgeView: View {
    let sessionState: SessionState

    var body: some View {
        switch sessionState {
        case .idle:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.gray)
        case .running:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.green)
        case .paused:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.orange)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.blue)
        case .stalled:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Preview

#Preview("All States") {
    HStack(spacing: 16) {
        ForEach(SessionState.allCases, id: \.self) { state in
            VStack(spacing: 4) {
                StatusBadgeView(sessionState: state)
                Text(state.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
}
