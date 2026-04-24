import SwiftUI
import AppKit

struct SessionSidebarView: View {
    @Binding var selection: SidebarItem?
    @Binding var showingNewSession: Bool
    @Environment(SessionStore.self) private var sessionStore
    @Environment(EngineManager.self) private var engineManager
    @State private var sessionToDelete: Session?
    @State private var sessionToRename: Session?
    @State private var missingEntryToDelete: SessionRegistryEntry?
    @State private var missingEntryToRelocate: SessionRegistryEntry?
    @State private var inlineRenamingID: Session.ID?
    @State private var inlineRenameName: String = ""
    @FocusState private var inlineRenameFocused: Bool
    @AppStorage("diffViewerCommand") private var diffViewerCommand: String = DiffViewerLauncher.defaultCommand
    @AppStorage("editorCommand") private var editorCommand: String = EditorOption.xcode.shellCommand
    @AppStorage("terminalCommand") private var terminalCommand: String = TerminalOption.terminal.shellCommand

    private var selectedSession: Session? {
        guard case .session(let id) = selection else { return nil }
        return sessionStore.sessions.first(where: { $0.id == id })
    }

    private var selectedMissingEntry: SessionRegistryEntry? {
        guard case .session(let id) = selection else { return nil }
        return sessionStore.missingSessions.first(where: { $0.id == id })
    }

    var body: some View {
        ZStack {
            List(selection: $selection) {
                Label("Home", systemImage: "house")
                    .tag(SidebarItem.home)

                ForEach(groupedDirectories, id: \.directory) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            sessionRowView(for: session)
                                .tag(SidebarItem.session(session.id))
                                .contextMenu {
                                    Button("Open in Finder") {
                                        openInFinder(session: session)
                                    }
                                    .keyboardShortcut("r", modifiers: [.command, .shift])
                                    Button("Open in Editor") {
                                        openInEditor(session: session)
                                    }
                                    .keyboardShortcut("e", modifiers: [.command, .shift])
                                    Button("Open in Terminal") {
                                        openInTerminal(session: session)
                                    }
                                    .keyboardShortcut("t", modifiers: [.command, .shift])
                                    Button("Open in Diff Viewer") {
                                        openInDiffViewer(session: session)
                                    }
                                    .keyboardShortcut("d", modifiers: [.command, .shift])
                                    Button("Rename…") {
                                        sessionToRename = session
                                    }
                                    .keyboardShortcut(.return, modifiers: [])
                                    Divider()
                                    Button("Delete Session", role: .destructive) {
                                        sessionToDelete = session
                                    }
                                    .keyboardShortcut("d", modifiers: .command)
                                }
                        }
                        ForEach(group.missing, id: \.id) { entry in
                            MissingSessionCardView(entry: entry)
                                .tag(SidebarItem.session(entry.id))
                                .contextMenu {
                                    Button("Relocate…") {
                                        missingEntryToRelocate = entry
                                    }
                                    Divider()
                                    Button("Delete Session", role: .destructive) {
                                        missingEntryToDelete = entry
                                    }
                                }
                        }
                    } header: {
                        Text(lastPathComponent(of: group.directory))
                            .help(group.directory)
                    }
                }
            }
            .listStyle(.sidebar)
            .onKeyPress(.return) {
                guard let session = selectedSession, inlineRenamingID == nil else { return .ignored }
                startInlineRename(session: session)
                return .handled
            }

            // F2 rename shortcut — menu bar covers the rest
            Button("") {
                if let session = selectedSession, inlineRenamingID == nil {
                    startInlineRename(session: session)
                }
            }
            // F2 = NSF2FunctionKey = U+F705
            .keyboardShortcut(KeyEquivalent("\u{F705}"), modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .navigationTitle("AW")
        .toolbar {
            ToolbarItem {
                Button {
                    showingNewSession = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Session (⌘T)")
            }
        }
        .alert("Delete Session?", isPresented: .init(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Delete (⌘D)", role: .destructive) {
                if let session = sessionToDelete {
                    engineManager.removeEngine(for: session.id)
                    try? sessionStore.deleteSession(session)
                    if selection == .session(session.id) {
                        selection = .home
                    }
                }
                sessionToDelete = nil
            }
            .keyboardShortcut("d", modifiers: .command)
        } message: {
            if let session = sessionToDelete {
                Text("Are you sure you want to delete \"\(session.name)\"? This cannot be undone.")
            }
        }
        .alert("Delete Session?", isPresented: .init(
            get: { missingEntryToDelete != nil },
            set: { if !$0 { missingEntryToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                missingEntryToDelete = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Delete (⌘D)", role: .destructive) {
                if let entry = missingEntryToDelete {
                    sessionStore.deleteMissingSession(id: entry.id)
                }
                missingEntryToDelete = nil
            }
            .keyboardShortcut("d", modifiers: .command)
        } message: {
            if let entry = missingEntryToDelete {
                Text("Are you sure you want to delete \"\(entry.name)\"? This cannot be undone.")
            }
        }
        .sheet(item: $sessionToRename) { session in
            RenameSessionSheet(
                initialName: session.name,
                onSave: { newName in
                    try? sessionStore.rename(sessionID: session.id, to: newName, manual: true)
                    sessionToRename = nil
                },
                onCancel: {
                    sessionToRename = nil
                }
            )
        }
        .sheet(item: $missingEntryToRelocate) { entry in
            RelocateSessionSheet(
                entry: entry,
                onRelocate: { newPath in
                    try sessionStore.relocateMissingSession(id: entry.id, to: newPath)
                    missingEntryToRelocate = nil
                },
                onCancel: {
                    missingEntryToRelocate = nil
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .awSessionOpenInFinder)) { _ in
            if let session = selectedSession { openInFinder(session: session) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .awSessionOpenInEditor)) { _ in
            if let session = selectedSession { openInEditor(session: session) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .awSessionOpenInTerminal)) { _ in
            if let session = selectedSession { openInTerminal(session: session) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .awSessionOpenInDiffViewer)) { _ in
            if let session = selectedSession { openInDiffViewer(session: session) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .awSessionRename)) { _ in
            if let session = selectedSession, inlineRenamingID == nil {
                startInlineRename(session: session)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .awSessionDelete)) { _ in
            if let session = selectedSession {
                sessionToDelete = session
            } else if let entry = selectedMissingEntry {
                missingEntryToDelete = entry
            }
        }
        .onChange(of: selection) { _, newSelection in
            guard let renamingID = inlineRenamingID else { return }
            if newSelection != .session(renamingID) {
                commitInlineRename()
            }
        }
    }

    @ViewBuilder
    private func sessionRowView(for session: Session) -> some View {
        if inlineRenamingID == session.id {
            TextField("Session name", text: $inlineRenameName)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($inlineRenameFocused)
                .onSubmit { commitInlineRename() }
                .onExitCommand { inlineRenamingID = nil }
                .onAppear { inlineRenameFocused = true }
        } else {
            SessionCardView(session: session)
        }
    }

    private func startInlineRename(session: Session) {
        inlineRenameName = session.name
        inlineRenamingID = session.id
    }

    private func commitInlineRename() {
        guard let id = inlineRenamingID else { return }
        let trimmed = inlineRenameName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            try? sessionStore.rename(sessionID: id, to: trimmed, manual: true)
        }
        inlineRenamingID = nil
    }

    private func openInDiffViewer(session: Session) {
        DiffViewerLauncher.launch(
            commandTemplate: diffViewerCommand,
            workingDirectory: session.workingDirectory
        )
    }

    private func openInEditor(session: Session) {
        DiffViewerLauncher.launch(
            commandTemplate: editorCommand,
            workingDirectory: session.workingDirectory
        )
    }

    private func openInTerminal(session: Session) {
        DiffViewerLauncher.launch(
            commandTemplate: terminalCommand,
            workingDirectory: session.workingDirectory
        )
    }

    private func openInFinder(session: Session) {
        let sessionDir = SessionDirectoryLayout.sessionDirectory(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: session.id
        )
        NSWorkspace.shared.activateFileViewerSelecting([sessionDir])
    }

    private struct DirectoryGroup {
        let directory: String
        let sessions: [Session]
        let missing: [SessionRegistryEntry]
    }

    private var groupedDirectories: [DirectoryGroup] {
        let reachableGrouped = Dictionary(grouping: sessionStore.sessions, by: \.workingDirectory)
        let missingGrouped = Dictionary(grouping: sessionStore.missingSessions, by: \.workingDirectory)
        let allDirectories = Set(reachableGrouped.keys).union(missingGrouped.keys)
        return allDirectories.sorted().map { directory in
            DirectoryGroup(
                directory: directory,
                sessions: reachableGrouped[directory] ?? [],
                missing: missingGrouped[directory] ?? []
            )
        }
    }

    private func lastPathComponent(of path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

private struct MissingSessionCardView: View {
    let entry: SessionRegistryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.name)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                Text("Missing")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Text((entry.workingDirectory as NSString).abbreviatingWithTildeInPath)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .opacity(0.5)
    }
}

private struct RenameSessionSheet: View {
    let initialName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String

    init(initialName: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialName = initialName
        self.onSave = onSave
        self.onCancel = onCancel
        self._name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Session")
                .font(.headline)
            TextField("Session name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 300)
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(name) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}

private struct RelocateSessionSheet: View {
    let entry: SessionRegistryEntry
    let onRelocate: (String) throws -> Void
    let onCancel: () -> Void

    @State private var selectedPath: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Relocate Session")
                .font(.headline)
            Text("Choose the Working Directory that contains the session data for \"\(entry.name)\".")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let path = selectedPath {
                    Text(path)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No folder selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose Folder…") {
                    pickFolder()
                }
            }
            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Relocate") {
                    guard let path = selectedPath else { return }
                    do {
                        try onRelocate(path)
                    } catch {
                        errorMessage = "That folder does not contain the session data for \"\(entry.name)\"."
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPath == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the Working Directory that contains the \"\(entry.name)\" session"
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
            errorMessage = nil
        }
    }
}
