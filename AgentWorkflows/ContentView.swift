import SwiftUI

/// Observable object to bridge the "show new session" action across the focus
/// system without publishing a new Binding struct each frame.
@Observable
final class NewSessionAction {
    var show = false
}

struct ShowNewSessionKey: FocusedValueKey {
    typealias Value = NewSessionAction
}

extension FocusedValues {
    var showNewSession: NewSessionAction? {
        get { self[ShowNewSessionKey.self] }
        set { self[ShowNewSessionKey.self] = newValue }
    }
}

extension Notification.Name {
    static let awShowNewSession = Notification.Name("AWShowNewSession")
    static let awNewSessionSameFolder = Notification.Name("AWNewSessionSameFolder")
    static let awToggleInspector = Notification.Name("AWToggleInspector")
    static let awCycleSessionForward = Notification.Name("AWCycleSessionForward")
    static let awCycleSessionBackward = Notification.Name("AWCycleSessionBackward")
    static let awSessionTogglePlayback = Notification.Name("AWSessionTogglePlayback")
    static let awSessionOpenInFinder = Notification.Name("AWSessionOpenInFinder")
    static let awSessionOpenInEditor = Notification.Name("AWSessionOpenInEditor")
    static let awSessionOpenInTerminal = Notification.Name("AWSessionOpenInTerminal")
    static let awSessionOpenInDiffViewer = Notification.Name("AWSessionOpenInDiffViewer")
    static let awSessionCopyPath = Notification.Name("AWSessionCopyPath")
    static let awSessionCopyCachePath = Notification.Name("AWSessionCopyCachePath")
    static let awSessionRename = Notification.Name("AWSessionRename")
    static let awSessionDelete = Notification.Name("AWSessionDelete")
    static let awSessionMarkStepComplete = Notification.Name("AWSessionMarkStepComplete")
}

struct IsSessionSelectedKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var isSessionSelected: Bool? {
        get { self[IsSessionSelectedKey.self] }
        set { self[IsSessionSelectedKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(WindowManager.self) private var windowManager
    @Environment(SettingsStore.self) private var settingsStore
    @SceneStorage("selectedItem") private var storedItem: SidebarItem = .home
    @State private var newSessionAction = NewSessionAction()
    @State private var windowNumber: Int?
    @State private var presenceReport: PresenceChecker.Report?
    @State private var presenceDismissed = false
    @AppStorage("firstRunSkillsModalDontShowAgain") private var dontShowFirstRunModal = false
    @State private var showFirstRunModal = false
    @State private var firstRunModalShown = false
    @State private var installResults: [SkillInstallExecutor.OpResult] = []
    @State private var installBlocked: [SkillInstaller.BlockedOp] = []
    @State private var showInstallResults = false

    /// The current selection as Optional — bridges @SceneStorage (non-optional) to List(selection:) (optional).
    private var selectedItem: SidebarItem? {
        get { storedItem }
        nonmutating set { storedItem = newValue ?? .home }
    }

    private var selectedItemBinding: Binding<SidebarItem?> {
        Binding(
            get: { storedItem },
            set: { storedItem = $0 ?? .home }
        )
    }

    private var showNewSessionBinding: Binding<Bool> {
        Binding(get: { newSessionAction.show }, set: { newSessionAction.show = $0 })
    }

    var body: some View {
        NavigationSplitView {
            SessionSidebarView(selection: selectedItemBinding, showingNewSession: showNewSessionBinding)
        } detail: {
            mainContent
        }
        .background {
            WindowNumberAccessor(windowNumber: $windowNumber)
            FocusedValuePublisher(action: newSessionAction, isSessionSelected: sessionIsSelected)
        }
        .sheet(isPresented: showNewSessionBinding) {
            NewSessionView(
                selection: selectedItemBinding,
                defaultWorkingDirectory: selectedSessionDirectory
            )
        }
        .sheet(isPresented: $showFirstRunModal) {
            if let report = presenceReport {
                FirstRunSkillsModal(
                    skillsDirectory: settingsStore.settings.planCLI.skillsDirectory
                        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills", isDirectory: true),
                    onInstall: {
                        showFirstRunModal = false
                        installMissingSkills(report: report)
                    },
                    onSkip: { showFirstRunModal = false },
                    onDontShowAgain: {
                        dontShowFirstRunModal = true
                        showFirstRunModal = false
                    }
                )
            }
        }
        .sheet(isPresented: $showInstallResults) {
            SkillInstallResultSheet(
                results: installResults,
                blocked: installBlocked,
                onDismiss: { showInstallResults = false },
                onRetry: SkillInstallResultSheet.hasFailures(in: installResults) ? {
                    showInstallResults = false
                    DispatchQueue.main.async { retryInstall() }
                } : nil
            )
        }
        .onAppear { updatePerRepoURL(for: storedItem) }
        .onChange(of: settingsStore.settings.allSkillTargets) { _, _ in
            evaluatePresence()
        }
        .onChange(of: storedItem) { oldValue, newValue in
            handleSelectionChange(from: oldValue, to: newValue)
            updatePerRepoURL(for: newValue)
        }
        .onChange(of: windowNumber) { _, newWN in
            if let newWN, case .session(let id) = selectedItem {
                windowManager.register(sessionID: id, windowNumber: newWN)
            }
        }
        .onChange(of: sessionStore.sessions) { _, sessions in
            // If the selected session was deleted from reachable list and also not missing, fall back to Home
            if case .session(let id) = selectedItem,
               !sessions.contains(where: { $0.id == id }),
               !sessionStore.missingSessions.contains(where: { $0.id == id }) {
                storedItem = .home
            }
        }
        .onChange(of: sessionStore.missingSessions) { _, missing in
            // If the selected missing session was deleted, fall back to Home
            if case .session(let id) = selectedItem,
               !missing.contains(where: { $0.id == id }),
               !sessionStore.sessions.contains(where: { $0.id == id }) {
                storedItem = .home
            }
        }
        .onDisappear {
            if let wn = windowNumber {
                windowManager.unregister(windowNumber: wn)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .awShowNewSession)) { _ in
            newSessionAction.show = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .awNewSessionSameFolder)) { _ in
            createSessionSameFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .awCycleSessionForward)) { _ in
            cycleSession(forward: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .awCycleSessionBackward)) { _ in
            cycleSession(forward: false)
        }
        .overlay {
            ZStack {
                Button("") { cycleSession(forward: true) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .hidden()
                Button("") { cycleSession(forward: false) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .hidden()
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        mainContentBody
            .navigationTitle(navigationTitle)
            .navigationSubtitle(navigationSubtitle)
            .task { evaluatePresenceAndCheckModal() }
    }

    @ViewBuilder
    private var bannerView: some View {
        if let report = presenceReport,
           !presenceDismissed,
           PresenceBanner.hasMissing(report) {
            PresenceBanner(report: report, onDismiss: { presenceDismissed = true }, onInstall: {
                installMissingSkills(report: report)
            })
        }
    }

    @ViewBuilder
    private var mainContentBody: some View {
        switch selectedItem {
        case .home, .none:
            VStack(spacing: 0) {
                bannerView
                HomeView(selection: selectedItemBinding, showingNewSession: showNewSessionBinding)
            }
        case .session(let id):
            if let session = sessionStore.sessions.first(where: { $0.id == id }) {
                SessionDetailView(session: session) {
                    bannerView
                }
                .id(session.id)
            } else if let entry = sessionStore.missingSessions.first(where: { $0.id == id }) {
                MissingSessionDetailView(entry: entry)
                    .id(entry.id)
            } else {
                Text("Session not found")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func evaluatePresence() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        presenceReport = PresenceChecker.check(
            skillTargets: settingsStore.settings.allSkillTargets,
            globalSettingsPath: home.appendingPathComponent(".claude/settings.json"),
            projectSettingsPath: nil
        )
    }

    private func evaluatePresenceAndCheckModal() {
        evaluatePresence()
        guard !firstRunModalShown,
              let report = presenceReport,
              FirstRunSkillsModal.shouldPresent(
                hasMissingSkills: !report.allSkillsPresent,
                dontShowAgain: dontShowFirstRunModal
              ) else { return }
        showFirstRunModal = true
        firstRunModalShown = true
    }

    private func installMissingSkills(report: PresenceChecker.Report) {
        guard let bundle = try? SkillBundleReader.read() else { return }
        var allResults: [SkillInstallExecutor.OpResult] = []
        var allBlocked: [SkillInstaller.BlockedOp] = []
        for target in selectedSkillTargets() {
            let dir = target.directory
            let inputs = PresenceBanner.installInputsForMissing(report: report, directory: dir, bundledSkills: bundle.skills)
            guard !inputs.isEmpty else { continue }
            let plan = SkillInstaller.plan(skills: inputs, intent: .firstRun)
            let results = SkillInstallExecutor.execute(plan: plan, skillsDirectory: dir, target: target)
            allResults.append(contentsOf: results)
            allBlocked.append(contentsOf: plan.blocked)
        }
        evaluatePresence()
        if SkillInstallResultSheet.shouldPresent(results: allResults, blocked: allBlocked) {
            installResults = allResults
            installBlocked = allBlocked
            showInstallResults = true
        }
    }

    private func retryInstall() {
        evaluatePresence()
        guard let report = presenceReport else { return }
        installMissingSkills(report: report)
    }

    private func selectedSkillTargets() -> [SkillTarget] {
        let targets: [SkillTarget?] = [
            settingsStore.settings.sidebarTitleProvider.cliPreset?.skillTarget,
            settingsStore.settings.planCLI.skillTarget,
            settingsStore.settings.verifyCLI.skillTarget,
            settingsStore.settings.buildCLI.skillTarget,
        ]

        var seen = Set<String>()
        return targets
            .compactMap { $0 }
            .filter { seen.insert($0.rawValue).inserted }
    }

    private var navigationTitle: String {
        switch selectedItem {
        case .home, .none:
            return "AW"
        case .session(let id):
            return sessionStore.sessions.first(where: { $0.id == id })?.name ?? "AW"
        }
    }

    private var navigationSubtitle: String {
        switch selectedItem {
        case .home, .none:
            return ""
        case .session(let id):
            guard let session = sessionStore.sessions.first(where: { $0.id == id }) else { return "" }
            return URL(fileURLWithPath: session.workingDirectory).lastPathComponent
        }
    }

    private var sessionIsSelected: Bool {
        if case .session = storedItem { return true }
        return false
    }

    private func createSessionSameFolder() {
        guard case .session(let id) = storedItem,
              let session = sessionStore.sessions.first(where: { $0.id == id }) else { return }
        if let newSession = try? sessionStore.createSession(
            workingDirectory: session.workingDirectory,
            workflowName: session.workflowName
        ) {
            storedItem = .session(newSession.id)
        }
    }

    private var selectedSessionDirectory: String? {
        guard case .session(let id) = selectedItem,
              let session = sessionStore.sessions.first(where: { $0.id == id }),
              session.workingDirectory != NSHomeDirectory() else {
            return nil
        }
        return session.workingDirectory
    }

    private func updatePerRepoURL(for item: SidebarItem) {
        switch item {
        case .home:
            settingsStore.setPerRepoURL(nil)
        case .session(let id):
            if let session = sessionStore.sessions.first(where: { $0.id == id }) {
                let url = URL(fileURLWithPath: session.workingDirectory)
                    .appendingPathComponent(".aw")
                    .appendingPathComponent("settings.json")
                settingsStore.setPerRepoURL(url)
            } else {
                settingsStore.setPerRepoURL(nil)
            }
        }
    }

    private var orderedSessions: [Session] {
        let grouped = Dictionary(grouping: sessionStore.sessions, by: \.workingDirectory)
        return grouped.keys.sorted().flatMap { grouped[$0] ?? [] }
    }

    private func cycleSession(forward: Bool) {
        let sessions = orderedSessions
        guard !sessions.isEmpty else { return }
        if case .session(let currentID) = storedItem,
           let idx = sessions.firstIndex(where: { $0.id == currentID }) {
            let nextIdx = forward
                ? (idx + 1) % sessions.count
                : (idx - 1 + sessions.count) % sessions.count
            storedItem = .session(sessions[nextIdx].id)
        } else {
            storedItem = .session((forward ? sessions.first : sessions.last)!.id)
        }
    }

    private func handleSelectionChange(from oldValue: SidebarItem, to newValue: SidebarItem) {
        // Unregister old session from this window
        if let wn = windowNumber {
            windowManager.unregister(windowNumber: wn)
        }

        // If navigating to a session, check for duplicates
        if case .session(let id) = newValue {
            if windowManager.focusWindow(for: id) {
                // Session is already open in another window — revert selection
                storedItem = oldValue
                return
            }
            // Register this window as showing the session
            if let wn = windowNumber {
                windowManager.register(sessionID: id, windowNumber: wn)
            }
        }
    }
}

// MARK: - Focused Value Publisher

/// Publishes the NewSessionAction as a focused scene value from a stable view
/// that doesn't re-evaluate when ContentView's other state changes.
/// This prevents "FocusedValue update tried to update multiple times per frame".
private struct FocusedValuePublisher: View {
    let action: NewSessionAction
    let isSessionSelected: Bool
    var body: some View {
        Color.clear
            .focusedSceneValue(\.showNewSession, action)
            .focusedSceneValue(\.isSessionSelected, isSessionSelected)
    }
}

// MARK: - Window Number Accessor

private struct WindowNumberAccessor: NSViewRepresentable {
    @Binding var windowNumber: Int?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            let num = view.window?.windowNumber
            if num != self.windowNumber {
                self.windowNumber = num
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let newNumber = nsView.window?.windowNumber
        guard newNumber != windowNumber else { return }
        DispatchQueue.main.async {
            self.windowNumber = newNumber
        }
    }
}

#Preview {
    ContentView()
        .environment(SessionStore(registryURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-preview-sessions.json")))
        .environment(WindowManager())
}
