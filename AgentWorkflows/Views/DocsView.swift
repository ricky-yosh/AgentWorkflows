import SwiftUI
import AppKit

// MARK: - File Scanner

enum DocsFileScanner {
    static let hiddenFiles: Set<String> = ["state.json"]

    static func isHidden(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return hiddenFiles.contains(name) || name.hasPrefix("step-complete-")
    }

    static func scanDirectory(_ directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        return contents
            .filter { url in
                let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                return isFile && !isHidden(url)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func scanDirectoryRecursive(_ directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return (enumerator.allObjects as? [URL] ?? [])
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

// MARK: - DocsView

struct DocsView: View {
    let session: Session
    @Environment(SessionStore.self) private var sessionStore

    @State private var files: [URL] = []
    @State private var projectFiles: [URL] = []
    @State private var leftFile: URL?
    @State private var rightFile: URL?
    @State private var isSplit = false
    @State private var focusedPane: Pane = .left
    @State private var watcher = DirectoryWatcher()
    @State private var awWatcher = DirectoryWatcher()

    private enum Pane { case left, right }

    private var sessionDirectory: URL {
        sessionStore.sessionDirectoryURL(for: session)
    }

    private var awDirectory: URL {
        URL(fileURLWithPath: session.workingDirectory).appendingPathComponent(".aw")
    }

    var body: some View {
        HSplitView {
            fileList
                .frame(minWidth: 160, idealWidth: 200, maxWidth: 280)

            contentArea
        }
        .task(id: session.id) {
            refreshFileList()
            refreshProjectFiles()
            watcher.watch(directory: sessionDirectory)
            awWatcher.watch(directory: awDirectory)
        }
        .onChange(of: watcher.lastChangeDate) { _, _ in
            refreshFileList()
        }
        .onChange(of: awWatcher.lastChangeDate) { _, _ in
            refreshProjectFiles()
        }
        .onDisappear {
            watcher.stop()
            awWatcher.stop()
        }
    }

    // MARK: - File List

    private var fileList: some View {
        List(selection: Binding(
            get: { focusedPane == .left ? leftFile : rightFile },
            set: { newValue in
                if focusedPane == .left || !isSplit {
                    leftFile = newValue
                } else {
                    rightFile = newValue
                }
            }
        )) {
            if !projectFiles.isEmpty {
                Section("Project") {
                    ForEach(projectFiles, id: \.self) { url in
                        FileRowView(url: url)
                            .tag(url)
                    }
                }
            }
            Section("Session") {
                ForEach(files, id: \.self) { url in
                    FileRowView(url: url)
                        .tag(url)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if isSplit {
            HSplitView {
                DocsContentPaneView(
                    file: leftFile,
                    isFocused: focusedPane == .left,
                    isSplit: true,
                    onFocus: { focusedPane = .left },
                    onClose: { closeSplitPane(.left) },
                    onToggleSplit: {}
                )

                DocsContentPaneView(
                    file: rightFile,
                    isFocused: focusedPane == .right,
                    isSplit: true,
                    onFocus: { focusedPane = .right },
                    onClose: { closeSplitPane(.right) },
                    onToggleSplit: {}
                )
            }
        } else {
            DocsContentPaneView(
                file: leftFile,
                isFocused: true,
                isSplit: false,
                onFocus: {},
                onClose: {},
                onToggleSplit: {
                    isSplit = true
                    focusedPane = .right
                }
            )
        }
    }

    // MARK: - Actions

    private func refreshFileList() {
        files = DocsFileScanner.scanDirectory(sessionDirectory)
        if let leftFile, !files.contains(leftFile) && !projectFiles.contains(leftFile) {
            self.leftFile = nil
        }
        if let rightFile, !files.contains(rightFile) && !projectFiles.contains(rightFile) {
            self.rightFile = nil
        }
    }

    private func refreshProjectFiles() {
        projectFiles = DocsFileScanner.scanDirectoryRecursive(awDirectory)
        if let leftFile, !projectFiles.contains(leftFile) && !files.contains(leftFile) {
            self.leftFile = nil
        }
        if let rightFile, !projectFiles.contains(rightFile) && !files.contains(rightFile) {
            self.rightFile = nil
        }
    }

    private func closeSplitPane(_ pane: Pane) {
        isSplit = false
        focusedPane = .left
        switch pane {
        case .left:
            leftFile = rightFile
            rightFile = nil
        case .right:
            rightFile = nil
        }
    }
}

// MARK: - File Row

struct FileRowView: View {
    let url: URL

    var body: some View {
        HStack {
            Image(systemName: iconForExtension(url.pathExtension))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fileSizeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var fileSizeString: String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return "" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return "\(size / 1024) KB" }
        return String(format: "%.1f MB", Double(size) / 1_048_576)
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "md": return "doc.richtext"
        case "json": return "curlybraces"
        case "xml": return "chevron.left.forwardslash.chevron.right"
        case "yaml", "yml": return "doc.text"
        case "txt": return "doc.plaintext"
        case "swift": return "swift"
        default: return "doc"
        }
    }
}

// MARK: - Content Pane

struct DocsContentPaneView: View {
    let file: URL?
    let isFocused: Bool
    let isSplit: Bool
    var onFocus: () -> Void = {}
    var onClose: () -> Void = {}
    var onToggleSplit: () -> Void = {}

    @AppStorage("externalEditorPath") private var externalEditorPath: String = ""
    @State private var wordWrap: Bool = true

    private static func defaultWordWrap(for file: URL?) -> Bool {
        guard let ext = file?.pathExtension.lowercased() else { return true }
        return ext != "json" && ext != "xml"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(isFocused && isSplit ? Color.accentColor.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
        .onChange(of: file, initial: true) { _, newFile in
            wordWrap = Self.defaultWordWrap(for: newFile)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if let file {
                Text(file.lastPathComponent)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
            } else {
                Text("No file selected")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let file {
                Toggle("Wrap", isOn: $wordWrap)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Toggle word wrap")

                Button {
                    openInEditor(file)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("Open in External Editor")
            }

            if isSplit {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close pane")
            } else {
                Button(action: onToggleSplit) {
                    Image(systemName: "rectangle.split.2x1")
                }
                .buttonStyle(.borderless)
                .help("Split view")
                .disabled(file == nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let file {
            FileContentView(url: file, wordWrap: wordWrap)
        } else {
            Text("Select a file to view")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func openInEditor(_ file: URL) {
        if !externalEditorPath.isEmpty {
            let editorURL = URL(fileURLWithPath: externalEditorPath)
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([file], withApplicationAt: editorURL, configuration: config)
        } else {
            NSWorkspace.shared.open(file)
        }
    }
}

// MARK: - File Content Router

struct FileContentView: View {
    let url: URL
    let wordWrap: Bool
    @State private var content: String?
    @State private var loadError = false

    var body: some View {
        Group {
            if loadError {
                Text("Binary file — cannot display")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else if let content {
                rendererForExtension(content: content)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) {
            loadFile()
        }
    }

    private func loadFile() {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            content = text
            loadError = false
        } else {
            content = nil
            loadError = true
        }
    }

    @ViewBuilder
    private func rendererForExtension(content: String) -> some View {
        switch url.pathExtension.lowercased() {
        case "md":
            MarkdownContentView(content: content, wordWrap: wordWrap)
        case "json":
            JSONContentView(content: content, wordWrap: wordWrap)
        case "xml":
            XMLContentView(content: content, wordWrap: wordWrap)
        default:
            PlainTextContentView(content: content, wordWrap: wordWrap)
        }
    }
}

// MARK: - Plain Text Renderer

struct PlainTextContentView: View {
    let content: String
    var wordWrap: Bool = true

    var body: some View {
        if wordWrap {
            ScrollView(.vertical) {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ScrollView([.horizontal, .vertical]) {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding()
            }
        }
    }
}

// MARK: - Markdown Renderer

struct MarkdownContentView: View {
    let content: String
    var wordWrap: Bool = true

    var body: some View {
        ScrollView(.vertical) {
            MarkdownView(content: content)
                .frame(maxWidth: 590)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - JSON Renderer

private enum JSONValueType {
    case string, number, boolean, null
}

private enum JSONNode: Identifiable {
    case object(key: String, id: String, children: [JSONNode])
    case array(key: String, id: String, children: [JSONNode])
    case value(key: String, id: String, display: String, type: JSONValueType)

    var id: String {
        switch self {
        case .object(_, let id, _): return id
        case .array(_, let id, _): return id
        case .value(_, let id, _, _): return id
        }
    }

    var key: String {
        switch self {
        case .object(let key, _, _): return key
        case .array(let key, _, _): return key
        case .value(let key, _, _, _): return key
        }
    }

    static func build(from object: Any, key: String = "root", path: String = "") -> JSONNode {
        let id = path.isEmpty ? key : "\(path).\(key)"
        if let dict = object as? [String: Any] {
            let children = dict.keys.sorted().map { k in
                build(from: dict[k]!, key: k, path: id)
            }
            return .object(key: key, id: id, children: children)
        } else if let arr = object as? [Any] {
            let children = arr.enumerated().map { i, v in
                build(from: v, key: "[\(i)]", path: id)
            }
            return .array(key: key, id: id, children: children)
        } else if let str = object as? String {
            return .value(key: key, id: id, display: "\"\(str)\"", type: .string)
        } else if let num = object as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(num) {
                return .value(key: key, id: id, display: num.boolValue ? "true" : "false", type: .boolean)
            }
            return .value(key: key, id: id, display: "\(num)", type: .number)
        } else if object is NSNull {
            return .value(key: key, id: id, display: "null", type: .null)
        } else {
            return .value(key: key, id: id, display: "\(object)", type: .string)
        }
    }
}

struct JSONContentView: View {
    let content: String
    var wordWrap: Bool = false

    var body: some View {
        if let data = content.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) {
            let root = JSONNode.build(from: parsed)
            ScrollView(wordWrap ? [.vertical] : [.horizontal, .vertical]) {
                JSONNodeView(node: root, isRoot: true)
                    .padding()
                    .frame(maxWidth: wordWrap ? .infinity : nil, alignment: .leading)
            }
        } else {
            PlainTextContentView(content: content, wordWrap: wordWrap)
        }
    }
}

private struct JSONNodeView: View {
    let node: JSONNode
    var isRoot: Bool = false

    var body: some View {
        switch node {
        case .object(let key, _, let children):
            VStack(alignment: .leading, spacing: 2) {
                if !isRoot {
                    Text("\(key): {")
                        .fontWeight(.medium)
                        .font(.system(.body, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(children) { child in
                        JSONNodeView(node: child)
                    }
                }
                .padding(.leading, isRoot ? 0 : 16)
                if !isRoot {
                    Text("}")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

        case .array(let key, _, let children):
            VStack(alignment: .leading, spacing: 2) {
                if !isRoot {
                    Text("\(key): [")
                        .fontWeight(.medium)
                        .font(.system(.body, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(children) { child in
                        JSONNodeView(node: child)
                    }
                }
                .padding(.leading, isRoot ? 0 : 16)
                if !isRoot {
                    Text("]")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

        case .value(let key, _, let display, let type):
            HStack(spacing: 0) {
                Text("\(key): ")
                    .fontWeight(.medium)
                    .font(.system(.body, design: .monospaced))
                Text(display)
                    .foregroundStyle(colorForType(type))
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private func colorForType(_ type: JSONValueType) -> Color {
        switch type {
        case .string: return .green
        case .number: return .blue
        case .boolean: return .orange
        case .null: return .gray
        }
    }
}

// MARK: - XML Renderer

struct XMLTreeNode: Identifiable {
    let id = UUID()
    let tag: String
    var attributes: [String: String]
    var textContent: String
    var children: [XMLTreeNode]
}

private class XMLTreeBuilder: NSObject, XMLParserDelegate {
    private var root: XMLTreeNode?
    private var stack: [XMLTreeNode] = []
    private var currentText = ""

    func parse(data: Data) -> XMLTreeNode? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse() ? root : nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        let node = XMLTreeNode(tag: elementName, attributes: attributes, textContent: "", children: [])
        stack.append(node)
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        guard var completed = stack.popLast() else { return }
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            completed.textContent = trimmed
        }
        if stack.isEmpty {
            root = completed
        } else {
            stack[stack.count - 1].children.append(completed)
        }
        currentText = ""
    }
}

struct XMLContentView: View {
    let content: String
    var wordWrap: Bool = false

    var body: some View {
        if let data = content.data(using: .utf8),
           let root = XMLTreeBuilder().parse(data: data) {
            if wordWrap {
                ScrollView(.vertical) {
                    XMLNodeView(node: root)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    XMLNodeView(node: root)
                        .padding()
                }
            }
        } else {
            PlainTextContentView(content: content, wordWrap: wordWrap)
        }
    }
}

private struct XMLNodeView: View {
    let node: XMLTreeNode

    var body: some View {
        if node.children.isEmpty && node.textContent.isEmpty {
            elementLabel
        } else if node.children.isEmpty {
            HStack(spacing: 4) {
                elementLabel
                Text(node.textContent)
                    .foregroundStyle(.secondary)
            }
        } else {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    if !node.textContent.isEmpty {
                        Text(node.textContent)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(node.children) { child in
                        XMLNodeView(node: child)
                    }
                }
                .padding(.leading, 12)
            } label: {
                elementLabel
            }
        }
    }

    private var elementLabel: some View {
        HStack(spacing: 4) {
            Text("<\(node.tag)>")
                .fontWeight(.medium)
                .foregroundStyle(.purple)
            if !node.attributes.isEmpty {
                Text(node.attributes.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " "))
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }
}
