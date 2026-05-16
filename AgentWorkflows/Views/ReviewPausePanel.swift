import SwiftUI
import AppKit

struct ReviewArtifact: Identifiable {
    let id: String
    let label: String
    let filename: String
}

/// Panel shown when the Workflow Engine is paused on a Review Pause Step.
/// Lists the Coordination Artifacts relevant to the preceding Phase and
/// provides a Continue button that advances the engine identically to the
/// toolbar Continue action.
struct ReviewPausePanel: View {
    let stepID: String
    let progressDirectoryURL: URL?
    let onContinue: () -> Void

    /// Maps a Review Pause Step ID to the Coordination Artifacts the user
    /// should inspect before continuing. Extracted for unit testability.
    static func artifacts(for stepID: String) -> [ReviewArtifact] {
        switch stepID {
        case "plan-review":
            return [
                ReviewArtifact(id: "prd", label: "PRD", filename: "PRD.md"),
                ReviewArtifact(id: "tasks", label: "Tasks File", filename: "tasks.json"),
            ]
        case "verify-review":
            return [
                ReviewArtifact(id: "qa", label: "QA output", filename: "tasks.json"),
            ]
        default:
            return []
        }
    }

    private var artifacts: [ReviewArtifact] {
        Self.artifacts(for: stepID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Review", systemImage: "checkmark.clipboard")
                .font(.headline)

            Divider()

            ForEach(artifacts) { artifact in
                HStack {
                    Text(artifact.label)
                        .font(.body)
                    Spacer()
                    if let dir = progressDirectoryURL {
                        Button("Open") {
                            NSWorkspace.shared.open(dir.appendingPathComponent(artifact.filename))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.thinMaterial)
    }
}
