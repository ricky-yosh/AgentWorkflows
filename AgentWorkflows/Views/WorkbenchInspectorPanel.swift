import AppKit
import SwiftUI

private enum WorkbenchInspectorPatternChoice: String, CaseIterable, Identifiable {
    case generic
    case observer
    case repository
    case adapter
    case factory
    case service
    case coordinator
    case delegate
    case custom

    var id: String { rawValue }

    var label: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    var modelValue: String {
        switch self {
        case .generic, .custom:
            return ""
        case .observer:
            return "Observer"
        case .repository:
            return "Repository"
        case .adapter:
            return "Adapter"
        case .factory:
            return "Factory"
        case .service:
            return "Service"
        case .coordinator:
            return "Coordinator"
        case .delegate:
            return "Delegate"
        }
    }

    static func choice(for pattern: String) -> WorkbenchInspectorPatternChoice {
        switch pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "generic":
            return .generic
        case "observer":
            return .observer
        case "repository":
            return .repository
        case "adapter":
            return .adapter
        case "factory":
            return .factory
        case "service":
            return .service
        case "coordinator":
            return .coordinator
        case "delegate":
            return .delegate
        default:
            return .custom
        }
    }
}

struct WorkbenchInspectorPanel: View {
    let session: Session
    let canvasFileStore: CanvasFileStore
    @Binding var selectedNodeName: String?
    @Binding var selectedConnection: Connection?

    @State private var nodeNameDraft = ""
    @State private var nodeRoleDraft = ""
    @State private var nodePinsDraft = ""
    @State private var patternChoice: WorkbenchInspectorPatternChoice = .generic
    @State private var customPatternDraft = ""
    @State private var connectionType: CanvasConnectionType = .calls
    @State private var isSyncingSelection = false

    private var selectedNode: SelectedNode? {
        guard let selectedNodeName else { return nil }
        if let node = canvasFileStore.model.inskirts.first(where: { $0.name == selectedNodeName }) {
            return .inskirts(node)
        }
        if let node = canvasFileStore.model.outskirts.first(where: { $0.name == selectedNodeName }) {
            return .outskirts(node)
        }
        return nil
    }

    private var selectionKey: String {
        if let selectedNodeName {
            return "node:\(selectedNodeName)"
        }
        if let selectedConnection {
            return "connection:\(selectedConnection.from)->\(selectedConnection.to):\(selectedConnection.type)"
        }
        return "none"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let selectedNode {
                        switch selectedNode {
                        case .inskirts(let node):
                            inskirtsEditor(for: node)
                        case .outskirts(let node):
                            outskirtsEditor(for: node)
                        }
                    } else if let selectedConnection {
                        connectionEditor(for: selectedConnection)
                    } else {
                        Text("Select a node or connection")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .task(id: selectionKey) {
            syncSelectionDrafts()
        }
        .onChange(of: nodeNameDraft) { _, _ in
            commitInskirtsDraftIfNeeded()
        }
        .onChange(of: nodeRoleDraft) { _, _ in
            commitInskirtsDraftIfNeeded()
        }
        .onChange(of: nodePinsDraft) { _, _ in
            commitInskirtsDraftIfNeeded()
        }
        .onChange(of: patternChoice) { _, newValue in
            guard !isSyncingSelection else { return }
            if newValue == .custom, customPatternDraft.isEmpty, let selectedNode {
                if case .inskirts(let node) = selectedNode {
                    customPatternDraft = node.pattern
                }
            }
            commitInskirtsDraftIfNeeded()
        }
        .onChange(of: customPatternDraft) { _, _ in
            commitInskirtsDraftIfNeeded()
        }
        .onChange(of: connectionType) { _, _ in
            commitConnectionDraftIfNeeded()
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Inspector")
                .font(.headline)
            Text(selectionSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var selectionSubtitle: String {
        if let selectedNode {
            switch selectedNode {
            case .inskirts(let node):
                return node.name
            case .outskirts(let node):
                return node.name
            }
        }
        if let selectedConnection {
            return "\(selectedConnection.from) → \(selectedConnection.to)"
        }
        return "Nothing selected"
    }

    @ViewBuilder
    private func inskirtsEditor(for node: InskirtsNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inskirts Node")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Name", text: $nodeNameDraft)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Pattern")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Pattern", selection: $patternChoice) {
                    ForEach(WorkbenchInspectorPatternChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.menu)

                if patternChoice == .custom {
                    TextField("Custom Pattern", text: $customPatternDraft)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Role Description")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Role Description", text: $nodeRoleDraft)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Pins (one per line)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $nodePinsDraft)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private func outskirtsEditor(for node: OutskirtsNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Outskirts Node")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(node.name)
                    .font(.callout.weight(.semibold))
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Source File")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(node.file)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Link("Open Source File", destination: sourceFileURL(for: node.file))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Role Description")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Role Description", text: $nodeRoleDraft)
            }

            Button(role: .destructive) {
                deleteOutskirtsNode(named: node.name)
            } label: {
                Text("Delete From Canvas")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    @ViewBuilder
    private func connectionEditor(for connection: Connection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            VStack(alignment: .leading, spacing: 6) {
                Text("From")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(connection.from)
                    .font(.callout.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("To")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(connection.to)
                    .font(.callout.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Type")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Type", selection: $connectionType) {
                    ForEach(CanvasConnectionType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func syncSelectionDrafts() {
        isSyncingSelection = true

        if let selectedNode {
            switch selectedNode {
            case .inskirts(let node):
                nodeNameDraft = node.name
                nodeRoleDraft = node.role
                nodePinsDraft = node.pins.joined(separator: "\n")
                patternChoice = WorkbenchInspectorPatternChoice.choice(for: node.pattern)
                customPatternDraft = patternChoice == .custom ? node.pattern : customPatternDraft
            case .outskirts(let node):
                nodeRoleDraft = node.role
            }
        }

        if let selectedConnection {
            connectionType = CanvasConnectionType(rawValue: selectedConnection.type) ?? .calls
        }

        Task { @MainActor in
            isSyncingSelection = false
        }
    }

    private func commitInskirtsDraftIfNeeded() {
        guard !isSyncingSelection, case .inskirts(let currentNode) = selectedNode else { return }

        let trimmedName = nodeNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            syncSelectionDrafts()
            return
        }

        let pattern = patternChoice == .custom ? customPatternDraft : patternChoice.modelValue
        let updatedNode = InskirtsNode(
            name: trimmedName,
            pattern: pattern,
            role: nodeRoleDraft,
            pins: Self.parsePins(from: nodePinsDraft)
        )

        var model = canvasFileStore.model
        guard model.updateInskirtsNode(named: currentNode.name, to: updatedNode) else {
            syncSelectionDrafts()
            return
        }

        try? canvasFileStore.save(model)
        selectedNodeName = updatedNode.name
    }

    private func commitConnectionDraftIfNeeded() {
        guard !isSyncingSelection, let connection = selectedConnection else { return }

        var model = canvasFileStore.model
        guard model.updateConnection(connection, type: connectionType.rawValue) else {
            syncSelectionDrafts()
            return
        }

        try? canvasFileStore.save(model)
        selectedConnection = Connection(from: connection.from, to: connection.to, type: connectionType.rawValue)
    }

    private func deleteOutskirtsNode(named name: String) {
        var model = canvasFileStore.model
        model.removeOutskirts(named: name)
        try? canvasFileStore.save(model)
        selectedNodeName = nil
        selectedConnection = nil
    }

    private func sourceFileURL(for relativePath: String) -> URL {
        URL(fileURLWithPath: relativePath, relativeTo: URL(fileURLWithPath: session.workingDirectory))
            .standardizedFileURL
    }

    private static func parsePins(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private enum SelectedNode {
        case outskirts(OutskirtsNode)
        case inskirts(InskirtsNode)
    }
}
