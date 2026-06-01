import SwiftUI
import AppKit

struct DiffFileTreeView: View {
    let fileDiffs: [FileDiff]
    let treeMode: DiffFileTreeMode
    @Binding var selectedFilePath: String?
    @Binding var expansionState: [String: Bool]

    private var treeNodes: [FileDiffNode] {
        FileDiffNode.buildTree(from: fileDiffs)
    }

    private var flatNodes: [FileDiffNode] {
        FileDiffNode.buildFlatList(from: fileDiffs)
    }

    var body: some View {
        Group {
            switch treeMode {
            case .tree:
                List(selection: $selectedFilePath) {
                    ForEach(treeNodes) { node in
                        DiffFileTreeNodeView(
                            node: node,
                            selectedFilePath: $selectedFilePath,
                            expansionState: $expansionState
                        )
                    }
                }
                .listStyle(.sidebar)
            case .flat:
                List(selection: $selectedFilePath) {
                    ForEach(flatNodes) { node in
                        DiffFileRow(node: node)
                            .tag(node.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

// MARK: - Tree node (recursive)

private struct DiffFileTreeNodeView: View {
    let node: FileDiffNode
    @Binding var selectedFilePath: String?
    @Binding var expansionState: [String: Bool]

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expansionState[node.id] ?? true },
            set: { expansionState[node.id] = $0 }
        )
    }

    var body: some View {
        if node.isDirectory, let children = node.children {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(children) { child in
                    DiffFileTreeNodeView(
                        node: child,
                        selectedFilePath: $selectedFilePath,
                        expansionState: $expansionState
                    )
                }
            } label: {
                DiffDirectoryRow(node: node)
            }
        } else {
            DiffFileRow(node: node)
                .tag(node.id)
        }
    }
}

// MARK: - Directory row

private struct DiffDirectoryRow: View {
    let node: FileDiffNode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .systemBlue))

            Text(node.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            HStack(spacing: 4) {
                if node.additions > 0 {
                    Text("+\(node.additions)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                }
                if node.removals > 0 {
                    Text("-\(node.removals)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .systemRed))
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.path, forType: .string)
            }
        }
    }
}

// MARK: - File row

private struct DiffFileRow: View {
    let node: FileDiffNode

    private var fileIcon: String {
        guard let diff = node.fileDiff else { return "doc" }
        let onlyAdds = diff.hunks.allSatisfy { $0.lines.allSatisfy { $0.kind != .removed } }
        let onlyRems = diff.hunks.allSatisfy { $0.lines.allSatisfy { $0.kind != .added } }
        if onlyAdds { return "doc.badge.plus" }
        if onlyRems { return "doc.badge.minus" }
        return "doc"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: fileIcon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if node.path != node.name {
                    Text(node.path)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if node.additions > 0 {
                    Text("+\(node.additions)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                }
                if node.removals > 0 {
                    Text("-\(node.removals)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .systemRed))
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Copy Relative Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.path, forType: .string)
            }
        }
    }
}
