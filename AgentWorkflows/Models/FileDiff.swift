import Foundation

struct FileDiff: Equatable {
    let filePath: String
    let hunks: [DiffHunk]
}

struct DiffHunk: Equatable {
    let contextLine: String
    let lines: [DiffLine]
}

struct DiffLine: Equatable {
    enum Kind { case added, removed, context }
    let kind: Kind
    let text: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

// MARK: - Tree model for file sidebar

struct FileDiffNode: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let children: [FileDiffNode]?
    let fileDiff: FileDiff?
    let additions: Int
    let removals: Int

    var isDirectory: Bool { children != nil }

    static func == (lhs: FileDiffNode, rhs: FileDiffNode) -> Bool {
        lhs.id == rhs.id && lhs.path == rhs.path
    }
}

extension FileDiffNode {
    static func buildTree(from fileDiffs: [FileDiff]) -> [FileDiffNode] {
        buildTree(from: fileDiffs, pathPrefix: "")
    }

    private static func buildTree(from fileDiffs: [FileDiff], pathPrefix: String) -> [FileDiffNode] {
        var groups: [String: [FileDiff]] = [:]
        for diff in fileDiffs {
            let first = diff.filePath.split(separator: "/").first.map(String.init) ?? diff.filePath
            groups[first, default: []].append(diff)
        }

        var result: [FileDiffNode] = []

        for (name, diffs) in groups.sorted(by: { $0.key < $1.key }) {
            let fullPath = pathPrefix.isEmpty ? name : "\(pathPrefix)/\(name)"
            if diffs.count == 1, diffs[0].filePath == name {
                // Single file at this level
                let diff = diffs[0]
                let adds = diff.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count }
                let rems = diff.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count }
                result.append(FileDiffNode(
                    id: fullPath, name: name, path: fullPath,
                    children: nil, fileDiff: diff, additions: adds, removals: rems
                ))
            } else {
                // Directory — strip the first component and recurse
                let stripped = diffs.map { diff -> FileDiff in
                    let comps = diff.filePath.split(separator: "/").map(String.init)
                    let rest = comps.dropFirst().joined(separator: "/")
                    return FileDiff(filePath: rest, hunks: diff.hunks)
                }
                let children = buildTree(from: stripped, pathPrefix: fullPath)
                let totalAdd = children.reduce(0) { $0 + $1.additions }
                let totalRem = children.reduce(0) { $0 + $1.removals }
                result.append(FileDiffNode(
                    id: fullPath, name: name, path: fullPath,
                    children: children, fileDiff: nil,
                    additions: totalAdd, removals: totalRem
                ))
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name < rhs.name
        }
    }

    static func buildFlatList(from fileDiffs: [FileDiff]) -> [FileDiffNode] {
        fileDiffs.map { diff in
            let additions = diff.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count }
            let removals = diff.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count }
            return FileDiffNode(
                id: diff.filePath,
                name: diff.filePath,
                path: diff.filePath,
                children: nil,
                fileDiff: diff,
                additions: additions,
                removals: removals
            )
        }.sorted { $0.name < $1.name }
    }
}

enum DiffFileTreeMode: String, CaseIterable, Identifiable {
    case tree
    case flat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tree: return "Tree"
        case .flat: return "List"
        }
    }

    var sfSymbol: String {
        switch self {
        case .tree: return "list.bullet.indent"
        case .flat: return "list.bullet"
        }
    }
}
