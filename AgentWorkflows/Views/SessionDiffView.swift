import SwiftUI
import AppKit
import Foundation

struct SessionDiffView: View {
    let session: Session

    @State private var fileDiffs: [FileDiff] = []
    @State private var rawDiff: String = ""
    @State private var loadError: String?
    @State private var isLoading = false

    @State private var selectedFilePath: String?
    @State private var treeMode: DiffFileTreeMode = .tree
    @State private var filterQuery: String = ""
    @State private var expansionState: [String: Bool] = [:]
    @State private var sidebarVisible: Bool = true

    private var filteredDiffs: [FileDiff] {
        guard !filterQuery.isEmpty else { return fileDiffs }
        return fileDiffs.filter { $0.filePath.localizedCaseInsensitiveContains(filterQuery) }
    }

    private var totalAdditions: Int {
        fileDiffs.reduce(0) { $0 + $1.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count } }
    }

    private var totalRemovals: Int {
        fileDiffs.reduce(0) { $0 + $1.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count } }
    }

    private var selectedDiffs: [FileDiff] {
        guard let selected = selectedFilePath else { return filteredDiffs }
        return filteredDiffs.filter {
            $0.filePath == selected || $0.filePath.hasPrefix(selected + "/")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()

            if let loadError {
                errorView(loadError)
            } else if isLoading {
                loadingView
            } else if fileDiffs.isEmpty {
                emptyView
            } else if filteredDiffs.isEmpty {
                noMatchesView
            } else {
                HSplitView {
                    if sidebarVisible {
                        DiffFileTreeView(
                            fileDiffs: filteredDiffs,
                            treeMode: treeMode,
                            selectedFilePath: $selectedFilePath,
                            expansionState: $expansionState
                        )
                        .frame(minWidth: 160, idealWidth: 200, maxWidth: 300)
                    }

                    SideBySideDiffView(
                        fileDiffs: sidebarVisible ? selectedDiffs : filteredDiffs,
                        scrollToFile: nil
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: session.id.uuidString) {
            await refresh()
        }
        .onChange(of: fileDiffs) { _, newDiffs in
            if selectedFilePath == nil || !newDiffs.contains(where: { $0.filePath == selectedFilePath }) {
                selectedFilePath = newDiffs.first?.filePath
            }
        }
        .onChange(of: filterQuery) { _, _ in
            guard let selected = selectedFilePath else { return }
            let stillVisible = filteredDiffs.contains {
                $0.filePath == selected || $0.filePath.hasPrefix(selected + "/")
            }
            if !stillVisible { selectedFilePath = filteredDiffs.first?.filePath }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    sidebarVisible.toggle()
                }
            } label: {
                Image(systemName: sidebarVisible ? "sidebar.left" : "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundStyle(sidebarVisible ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(sidebarVisible ? "Hide file sidebar" : "Show file sidebar")

            Divider().frame(height: 16)

            Button {
                treeMode = treeMode == .tree ? .flat : .tree
            } label: {
                Image(systemName: treeMode.sfSymbol)
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help(treeMode == .tree ? "Switch to flat list" : "Switch to tree view")
            .disabled(!sidebarVisible)

            if treeMode == .tree && !fileDiffs.isEmpty && sidebarVisible {
                Button { expandAll() } label: {
                    Image(systemName: "chevron.down.2")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Expand all folders")

                Button { collapseAll() } label: {
                    Image(systemName: "chevron.up.2")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Collapse all folders")
            }

            Divider().frame(height: 16)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Filter files...", text: $filterQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 160)

            if !filterQuery.isEmpty {
                Button { filterQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            if !fileDiffs.isEmpty {
                HStack(spacing: 8) {
                    Text("+\(totalAdditions)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    Text("-\(totalRemovals)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .systemRed))
                }
            }

            if !rawDiff.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(rawDiff, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Copy full patch to clipboard")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Parsing git diff...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.08))
                    .frame(width: 48, height: 48)
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(nsColor: .systemGreen))
            }
            VStack(spacing: 4) {
                Text("No Changes Detected")
                    .font(.system(size: 13, weight: .semibold))
                Text("Your working directory is clean.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var noMatchesView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 48, height: 48)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                Text("No Matching Files")
                    .font(.system(size: 13, weight: .semibold))
                Text("No files match \"\(filterQuery)\".")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20))
                .foregroundStyle(Color(nsColor: .systemOrange))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Expand / Collapse

    private func expandAll() {
        allDirectoryIDs(FileDiffNode.buildTree(from: fileDiffs)).forEach {
            expansionState[$0] = true
        }
    }

    private func collapseAll() {
        allDirectoryIDs(FileDiffNode.buildTree(from: fileDiffs)).forEach {
            expansionState[$0] = false
        }
    }

    private func allDirectoryIDs(_ nodes: [FileDiffNode]) -> [String] {
        nodes.flatMap { node -> [String] in
            guard let children = node.children else { return [] }
            return [node.id] + allDirectoryIDs(children)
        }
    }

    // MARK: - Refresh

    private func refresh() async {
        isLoading = true
        loadError = nil
        rawDiff = ""
        let workingDirectory = URL(fileURLWithPath: session.workingDirectory)
        let result = await Task.detached {
            SystemGitDiffRunner().run(workingDirectory: workingDirectory)
        }.value
        switch result {
        case .success(let output):
            rawDiff = output
            fileDiffs = GitDiffParser.parse(output)
            loadError = nil
        case .failure(let error):
            fileDiffs = []
            loadError = error.message
        }
        isLoading = false
    }
}

// MARK: - Git runner

nonisolated struct GitDiffError: Error, Equatable {
    let message: String
}

nonisolated protocol GitDiffRunner: Sendable {
    func run(workingDirectory: URL) -> Result<String, GitDiffError>
}

nonisolated struct SystemGitDiffRunner: GitDiffRunner {
    func run(workingDirectory: URL) -> Result<String, GitDiffError> {
        Self.runGit(["diff", "HEAD"], in: workingDirectory)
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

#Preview("Session Diff") {
    SessionDiffView(
        session: Session(
            id: UUID(),
            name: "Preview Session",
            workingDirectory: "/tmp/preview",
            workflowName: "Ralph",
            state: .idle,
            currentPhaseIndex: 0,
            currentStepIndex: 0,
            completedStepIDs: []
        )
    )
}
