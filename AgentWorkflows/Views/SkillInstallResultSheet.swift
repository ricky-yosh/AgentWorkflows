import SwiftUI

struct SkillInstallResultSheet: View {
    let results: [SkillInstallExecutor.OpResult]
    let blocked: [SkillInstaller.BlockedOp]
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Skill Install Results")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results, id: \.skillName) { result in
                        resultRow(result)
                    }
                    ForEach(blocked, id: \.skillName) { op in
                        blockedRow(op)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                if Self.hasFailures(in: results), let onRetry {
                    Button("Retry") { onRetry() }
                }
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 200)
    }

    @ViewBuilder
    private func resultRow(_ result: SkillInstallExecutor.OpResult) -> some View {
        HStack(alignment: .top, spacing: 8) {
            switch result.outcome {
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(result.skillName)
            case .failed(let message):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.skillName)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func blockedRow(_ op: SkillInstaller.BlockedOp) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(op.skillName)
                Text(op.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Static helpers (testable)

    static func hasFailures(in results: [SkillInstallExecutor.OpResult]) -> Bool {
        results.contains {
            if case .failed = $0.outcome { return true }
            return false
        }
    }

    static func shouldPresent(results: [SkillInstallExecutor.OpResult], blocked: [SkillInstaller.BlockedOp]) -> Bool {
        !results.isEmpty || !blocked.isEmpty
    }
}
