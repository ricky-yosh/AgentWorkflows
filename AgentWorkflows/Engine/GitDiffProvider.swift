import Foundation

// MARK: - Pure parser (stateless)

enum GitDiffParser {
    /// Extract the starting line number from a hunk range like "45,8" or just "45".
    private static func parseStart(_ s: Substring) -> Int {
        let numStr = s.split(separator: ",").first ?? s
        return Int(numStr) ?? 1
    }

    static func parse(_ output: String) -> [FileDiff] {
        guard !output.isEmpty else { return [] }

        var fileDiffs: [FileDiff] = []
        var currentFile: String?
        var currentHunks: [DiffHunk] = []
        var currentContextLine = ""
        var currentLines: [DiffLine] = []
        var oldLineNum: Int = 0
        var newLineNum: Int = 0

        func flushHunk() {
            guard !currentLines.isEmpty else { return }
            currentHunks.append(DiffHunk(contextLine: currentContextLine, lines: currentLines))
            currentLines = []
            currentContextLine = ""
        }

        func flushFile() {
            guard let file = currentFile else { return }
            flushHunk()
            if !currentHunks.isEmpty {
                fileDiffs.append(FileDiff(filePath: file, hunks: currentHunks))
            }
            currentHunks = []
        }

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git ") {
                flushFile()
                // "diff --git a/path/file.swift b/path/file.swift" — take b/ side
                currentFile = line.components(separatedBy: " b/").last
            } else if line.hasPrefix("@@ ") {
                flushHunk()
                // "@@ -45,8 +45,12 @@ func prepareDish() {" — take everything after second @@
                let parts = line.components(separatedBy: " @@ ")
                currentContextLine = parts.count > 1
                    ? parts[1].trimmingCharacters(in: .whitespaces)
                    : ""
                // Parse old start and new start from hunk header: @@ -oldStart[,oldCount] +newStart[,newCount] @@
                if let headerPart = parts.first {
                    let tokens = headerPart.split(separator: " ")
                    if tokens.count >= 3 {
                        oldLineNum = parseStart(tokens[1].dropFirst())  // drop leading "-"
                        newLineNum = parseStart(tokens[2].dropFirst())  // drop leading "+"
                    }
                }
            } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                currentLines.append(DiffLine(kind: .added, text: String(line.dropFirst()),
                    oldLineNumber: nil, newLineNumber: newLineNum))
                newLineNum += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                currentLines.append(DiffLine(kind: .removed, text: String(line.dropFirst()),
                    oldLineNumber: oldLineNum, newLineNumber: nil))
                oldLineNum += 1
            } else if line.hasPrefix(" ") {
                currentLines.append(DiffLine(kind: .context, text: String(line.dropFirst()),
                    oldLineNumber: oldLineNum, newLineNumber: newLineNum))
                oldLineNum += 1
                newLineNum += 1
            }
        }
        flushFile()
        return fileDiffs
    }
}

// MARK: - Observable provider

import Observation

@Observable
final class GitDiffProvider {
    private(set) var fileDiffs: [FileDiff] = []

    private var workingDirectory: URL?
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var directoryFD: Int32 = -1

    func start(workingDirectory: URL) {
        stop()  // cancel any prior source before creating a new one
        self.workingDirectory = workingDirectory
        // Dispatch initial refresh to background — runGitDiff blocks on waitUntilExit()
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.refresh() }
        startWatching(directory: workingDirectory)
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
        directoryFD = -1  // do NOT call Darwin.close here — cancel handler owns it
    }

    func refresh() {
        guard let dir = workingDirectory else { return }
        let output = runGitDiff(in: dir)
        DispatchQueue.main.async { [weak self] in
            self?.fileDiffs = GitDiffParser.parse(output)
        }
    }

    // MARK: - Private

    private func runGitDiff(in directory: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // "git diff HEAD" shows staged + unstaged — clears only on commit, not on git add
        process.arguments = ["diff", "HEAD"]
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()  // read BEFORE wait
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func startWatching(directory: URL) {
        // Watch .git/index — it is touched on every git add/restore/commit,
        // so it fires for any change that affects `git diff HEAD`. Watching the
        // working directory root (O_EVTONLY) only fires for direct children, not
        // subdirectory edits made by the agent.
        let indexURL = directory.appendingPathComponent(".git/index")
        let fd = Darwin.open(indexURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in self?.refresh() }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        dispatchSource = source
    }
}
