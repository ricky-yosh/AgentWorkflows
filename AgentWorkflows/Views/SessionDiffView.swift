import SwiftUI
import Foundation

/// Unified git-diff viewer for a Session's working directory.
///
/// Default scope is the last Ralph commit (`git diff HEAD~1..HEAD`). The
/// scope picker widens to the full Session (`git diff <base>..HEAD`) where
/// `<base>` is the merge-base with `main`. No AI-generated summary is
/// rendered — the raw unified diff is the only content.
struct SessionDiffView: View {
    let session: Session

    @State private var scope: Scope = .lastCommit
    @State private var fileDiffs: [FileDiff] = []
    @State private var loadError: String?

    private var totalAdditions: Int {
        fileDiffs.reduce(0) { $0 + $1.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count } }
    }

    private var totalRemovals: Int {
        fileDiffs.reduce(0) { $0 + $1.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count } }
    }

    enum Scope: String, CaseIterable, Identifiable {
        case lastCommit
        case fullSession

        var id: String { rawValue }

        var label: String {
            switch self {
            case .lastCommit: return "Last commit"
            case .fullSession: return "Full session"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Scope", selection: $scope) {
                    ForEach(Scope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Spacer()

                if !fileDiffs.isEmpty {
                    HStack(spacing: 8) {
                        Text("+\(totalAdditions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(hex: "#22863a"))
                        Text("-\(totalRemovals)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(hex: "#cb2431"))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()

            if let loadError {
                Text(loadError)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if fileDiffs.isEmpty {
                Text("No changes in the selected scope.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(fileDiffs.enumerated()), id: \.offset) { _, file in
                            SessionDiffFileView(file: file)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
        }
        .task(id: "\(session.id.uuidString)-\(scope.rawValue)") {
            await refresh()
        }
    }

    private func refresh() async {
        let workingDirectory = URL(fileURLWithPath: session.workingDirectory)
        let currentScope = scope
        let result = await Task.detached {
            SystemGitDiffRunner().run(scope: currentScope, workingDirectory: workingDirectory)
        }.value
        switch result {
        case .success(let output):
            fileDiffs = GitDiffParser.parse(output)
            loadError = nil
        case .failure(let error):
            fileDiffs = []
            loadError = error.message
        }
    }
}

// MARK: - Git runner

nonisolated struct GitDiffError: Error, Equatable {
    let message: String
}

nonisolated protocol GitDiffRunner: Sendable {
    func run(scope: SessionDiffView.Scope, workingDirectory: URL) -> Result<String, GitDiffError>
}

nonisolated struct SystemGitDiffRunner: GitDiffRunner {
    func run(scope: SessionDiffView.Scope, workingDirectory: URL) -> Result<String, GitDiffError> {
        switch scope {
        case .lastCommit:
            return Self.runGit(["diff", "HEAD~1..HEAD"], in: workingDirectory)
        case .fullSession:
            switch Self.findMergeBase(in: workingDirectory) {
            case .success(let base):
                return Self.runGit(["diff", "\(base)..HEAD"], in: workingDirectory)
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    // Tries common default-branch names in order so repos using "master" or
    // remote-tracking refs work without extra configuration.
    private static func findMergeBase(in directory: URL) -> Result<String, GitDiffError> {
        let candidates = ["main", "master", "origin/main", "origin/master", "origin/HEAD"]
        for branch in candidates {
            if case .success(let output) = Self.runGit(["merge-base", "HEAD", branch], in: directory) {
                let base = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !base.isEmpty { return .success(base) }
            }
        }
        return .failure(GitDiffError(
            message: "Cannot find a common ancestor. Make sure the branch diverges from main, master, or an origin remote."
        ))
    }

    static func runGit(_ arguments: [String], in directory: URL) -> Result<String, GitDiffError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let raw = String(data: errData, encoding: .utf8) ?? ""
                let message = raw.isEmpty ? "git exited with status \(process.terminationStatus)." : raw
                return .failure(GitDiffError(message: message))
            }
            return .success(String(data: data, encoding: .utf8) ?? "")
        } catch {
            return .failure(GitDiffError(message: error.localizedDescription))
        }
    }
}

// MARK: - Row rendering

private struct SessionDiffFileView: View {
    let file: FileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.filePath)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .underPageBackgroundColor))

            ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
                VStack(alignment: .leading, spacing: 0) {
                    if !hunk.contextLine.isEmpty {
                        Text(hunk.contextLine)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(hex: "#0366d6"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "#f1f8ff"))
                    }
                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                        SessionDiffLineRow(line: line)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct SessionDiffLineRow: View {
    let line: DiffLine

    private var rowColor: Color {
        switch line.kind {
        case .context: return .clear
        case .added: return .green.opacity(0.12)
        case .removed: return .red.opacity(0.12)
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .context: return .primary
        case .added: return .green
        case .removed: return .red
        }
    }

    private var marker: String {
        switch line.kind {
        case .context: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .context: return .clear
        case .added: return .green
        case .removed: return .red
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // Old line number column (40px)
            Text(line.oldLineNumber.map { "\($0)" } ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
                .allowsHitTesting(false)
            // New line number column (40px)
            Text(line.newLineNumber.map { "\($0)" } ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
                .allowsHitTesting(false)
            // Marker column (16px)
            Text(marker)
                .font(.system(size: 11, design: .monospaced).weight(.semibold))
                .foregroundStyle(markerColor)
                .frame(width: 16, alignment: .center)
            // Line text
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(rowColor)
    }
}
