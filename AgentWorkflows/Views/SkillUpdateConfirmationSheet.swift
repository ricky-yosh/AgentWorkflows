import SwiftUI

struct SkillUpdateConfirmationSheet: View {
    let skillName: String
    let bundledContent: String
    let onDiskContent: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Update \"\(skillName)\"?")
                .font(.headline)
            Text("This skill has been locally modified. Overwriting will replace your edits with the bundled version. Review the diff below.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                diffView
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Overwrite", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(24)
        .frame(minWidth: 560)
    }

    @ViewBuilder
    private var diffView: some View {
        let changes = Self.computeDiff(bundled: bundledContent, onDisk: onDiskContent)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                diffLine(change)
            }
        }
        .font(.system(.callout, design: .monospaced))
        .padding(8)
    }

    @ViewBuilder
    private func diffLine(_ change: DiffChange) -> some View {
        switch change {
        case .unchanged(let line):
            Text(" " + line)
                .foregroundStyle(.secondary)
        case .removed(let line):
            Text("-" + line)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
        case .added(let line):
            Text("+" + line)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
        }
    }

    enum DiffChange {
        case unchanged(String)
        case removed(String)  // in on-disk but not bundled (user's edits, will be lost)
        case added(String)    // in bundled but not on-disk (will be gained)
    }

    // Computes a line-level diff: old = on-disk, new = bundled.
    static func computeDiff(bundled: String, onDisk: String) -> [DiffChange] {
        let old = onDisk.components(separatedBy: "\n")
        let new = bundled.components(separatedBy: "\n")
        let m = old.count, n = new.count

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        if m > 0 && n > 0 {
            for i in 1...m {
                for j in 1...n {
                    dp[i][j] = old[i-1] == new[j-1]
                        ? dp[i-1][j-1] + 1
                        : max(dp[i-1][j], dp[i][j-1])
                }
            }
        }

        var changes: [DiffChange] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && old[i-1] == new[j-1] {
                changes.append(.unchanged(old[i-1]))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                changes.append(.added(new[j-1]))
                j -= 1
            } else {
                changes.append(.removed(old[i-1]))
                i -= 1
            }
        }
        return changes.reversed()
    }
}
