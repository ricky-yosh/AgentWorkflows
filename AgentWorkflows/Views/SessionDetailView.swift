import SwiftUI
import AppKit

/// Session detail layout: terminal in the center, workflow inspector on the right.
struct SessionDetailView<Header: View>: View {
    let session: Session
    @ViewBuilder let headerContent: Header

    @Environment(SessionStore.self) private var sessionStore
    @Environment(EngineManager.self) private var engineManager
    @Environment(SettingsStore.self) private var settingsStore

    @State private var inspectorPresented = false
    @State private var phaseExpansion: [AnyHashable: Bool] = [:]
    @State private var workflow: Workflow?

    /// Seed intent collected from the pre-Play modal. Held in memory for
    /// the session's lifetime — re-Play after stop/complete reuses the
    /// same seed without re-prompting.
    @State private var seedIdea: String?
    @State private var seedPromptPresented = false
    @State private var selectedTab: SessionTab = .iterations

    private enum SessionTab: Hashable {
        case iterations, files, diff, log, workflow
    }

    private var workflowEngine: WorkflowEngine? {
        engineManager.workflowEngine(for: session.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerContent
            SessionHeaderStatus(
                status: engineManager.runStatus(for: session.id),
                session: session,
                workflow: workflow
            )
            if let stepID = reviewPauseStepID {
                Divider()
                ReviewPausePanel(
                    stepID: stepID,
                    progressDirectoryURL: progressDirectoryURL,
                    onContinue: continueExecution
                )
            }
            tabbedBody
        }
        .onAppear {
            DispatchQueue.main.async {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { inspectorPresented = true }
            }
        }
            .inspector(isPresented: $inspectorPresented) {
                WorkflowInspector(
                    session: session,
                    workflow: workflow,
                    workflowEngine: workflowEngine,
                    phaseExpansion: $phaseExpansion,
                    onRunFromHere: runFromHere
                )
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    playStopButton
                    Button {
                        inspectorPresented.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.trailing")
                    }
                    .help("Toggle Inspector (⌃⌘I)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .awToggleInspector)) { _ in
                inspectorPresented.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .awSessionTogglePlayback)) { _ in
                togglePlayback()
            }
            .task(id: session.id) {
                selectedTab = .iterations
                phaseExpansion = [:]
                seedIdea = nil
                seedPromptPresented = false
                workflow = nil
                loadWorkflow()
                primeTaskCounts()
            }
            .onChange(of: session.workflowName) { _, _ in
                loadWorkflow()
            }
            .onChange(of: session.state) { _, newState in
                syncRunStatusState(newState)
            }
            .onChange(of: workflowEngine?.executionState) { _, newState in
                handleExecutionStateChange(newState)
            }
            .onChange(of: workflowEngine?.completedStepIDs) { _, _ in
                syncProgress()
            }
            .sheet(isPresented: $seedPromptPresented, onDismiss: focusTerminal) {
                SessionSeedSheet(
                    onConfirm: { text in
                        seedIdea = text
                        seedPromptPresented = false
                        let sessionID = session.id
                        let store = sessionStore
                        let titleBackend = try? ProcessRunnerFactory.makeTitleBackend(
                            provider: settingsStore.settings.sidebarTitleProvider
                        )
                        Task {
                            let synthesizer = DefaultSessionTitleSynthesizer(backend: titleBackend)
                            await writeSeedAndSynthesizeTitle(
                                text: text, sessionID: sessionID, store: store, synthesizer: synthesizer
                            )
                        }
                        startRalphLoop()
                    },
                    onCancel: { seedPromptPresented = false }
                )
            }
    }

    @ViewBuilder
    private var tabbedBody: some View {
        TabView(selection: $selectedTab) {
            IterationsView(
                sessionID: session.id,
                tasksFileURL: SessionDirectoryLayout.tasksFileURL(
                    workingDirectory: URL(fileURLWithPath: session.workingDirectory),
                    sessionID: session.id
                )
            )
            .tabItem { Label("Iterations", systemImage: "repeat") }
            .tag(SessionTab.iterations)

            DocsView(session: session)
                .tabItem { Label("Files", systemImage: "folder") }
                .tag(SessionTab.files)

            SessionDiffView(session: session)
                .tabItem { Label("Diff", systemImage: "plusminus") }
                .tag(SessionTab.diff)

            ExecutionLogTabView(sessionID: session.id)
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
                .tag(SessionTab.log)
        }
        .background(TabTooltipSetter(tooltips: [
            "Iterations (⌘1)",
            "Files (⌘2)",
            "Diff (⌘3)",
            "Log (⌘4)",
            "Workflow (⌘5)"
        ]))
        .overlay(tabShortcuts)
    }

    @ViewBuilder
    private var tabShortcuts: some View {
        ZStack {
            Button("") { selectedTab = .iterations }
                .keyboardShortcut("1", modifiers: .command)
                .hidden()
            Button("") { selectedTab = .files }
                .keyboardShortcut("2", modifiers: .command)
                .hidden()
            Button("") { selectedTab = .diff }
                .keyboardShortcut("3", modifiers: .command)
                .hidden()
            Button("") { selectedTab = .log }
                .keyboardShortcut("4", modifiers: .command)
                .hidden()
            Button("") { selectedTab = .workflow }
                .keyboardShortcut("5", modifiers: .command)
                .hidden()
        }
        .frame(width: 0, height: 0)
    }

    private func syncRunStatusState(_ state: SessionState) {
        let status = engineManager.runStatus(for: session.id)
        switch state {
        case .idle:
            status.driverState = .idle
            status.finishRun()
        case .running:
            status.driverState = .running
            if status.startedAt == nil {
                status.beginRun()
                if let dir = workflowEngine?.progressDirectoryPath {
                    let passes = WorkflowEngine.readPasses(progressDir: dir)
                    if !passes.isEmpty {
                        status.applyIteration(count: 0, passes: passes)
                    }
                }
            }
        case .paused:
            status.driverState = .paused
        case .completed:
            status.driverState = .completed
            status.finishRun()
        case .stalled:
            status.driverState = .stalled
            status.finishRun()
        }
    }

    @ViewBuilder
    private var playStopButton: some View {
        if workflow != nil {
            switch session.state {
            case .idle:
                Button(action: play) {
                    Image(systemName: "play.fill")
                }
                .help("Play Session (⌘↩)")
            case .running:
                Button(action: stop) {
                    Image(systemName: "stop.fill")
                }
                .help("Stop Session (⌘↩)")
            case .paused:
                Button(action: continueExecution) {
                    Image(systemName: "play.fill")
                }
                .help("Continue Session (⌘↩)")
            case .completed:
                Button(action: restartFromCompleted) {
                    Image(systemName: "play.fill")
                }
                .help("Restart completed session (⌘↩)")
            case .stalled:
                Button(action: continueExecution) {
                    Image(systemName: "play.fill")
                }
                .help("Continue stalled loop (⌘↩)")
            }
        }
    }

    /// Non-nil when the session is paused on a Pause Step whose label is
    /// "Review" — returns the step ID so `ReviewPausePanel` can select the
    /// correct artifact set.
    private var reviewPauseStepID: String? {
        guard session.state == .paused, let wf = workflow else { return nil }
        let phaseIndex = workflowEngine?.currentPhaseIndex ?? session.currentPhaseIndex
        let stepIndex = workflowEngine?.currentStepIndex ?? session.currentStepIndex
        guard phaseIndex < wf.phases.count else { return nil }
        let phase = wf.phases[phaseIndex]
        guard stepIndex < phase.steps.count else { return nil }
        let step = phase.steps[stepIndex]
        guard step.type == .pause, step.label == "Review" else { return nil }
        return step.id
    }

    private var progressDirectoryURL: URL? {
        SessionDirectoryLayout.sessionDirectory(
            workingDirectory: URL(fileURLWithPath: session.workingDirectory),
            sessionID: session.id
        )
    }

    private func focusTerminal() {
        let activeTool = engineManager.activeTools(for: session.id).last ?? engineManager.defaultAgent
        let terminalView = engineManager.engine(for: session.id, tool: activeTool).terminalView
        terminalView.window?.makeFirstResponder(terminalView)
    }

    private func loadWorkflow() {
        workflow = sessionStore.loadWorkflow(for: session)
    }

    private func primeTaskCounts() {
        guard let dir = progressDirectoryURL else { return }
        let passes = WorkflowEngine.readPasses(progressDir: dir.path)
        guard !passes.isEmpty else { return }
        let status = engineManager.runStatus(for: session.id)
        status.tasksPassed = passes.filter { $0 }.count
        status.tasksTotal = passes.count
    }

    private func play() {
        guard workflow != nil else { return }
        // Show seed sheet only when plan-grill-with-docs has not yet run. Once it
        // completes its ID lands in session.completedStepIDs (persisted to
        // disk), so re-Play after Stop never re-prompts. Cancel leaves the
        // session in .idle by not calling startRalphLoop.
        if !session.completedStepIDs.contains("plan-grill-with-docs") {
            seedPromptPresented = true
            return
        }
        startRalphLoop()
    }

    private func togglePlayback() {
        guard workflow != nil else { return }
        switch session.state {
        case .idle:
            play()
        case .running:
            stop()
        case .paused, .stalled:
            continueExecution()
        case .completed:
            restartFromCompleted()
        }
    }

    private func startRalphLoop() {
        guard let workflow else { return }
        do {
            try sessionStore.transitionSession(session.id, to: .running)
        } catch {
            return
        }
        ensureTerminalRunning(phaseIndex: session.currentPhaseIndex)
        let workflowEngine = engineManager.createWorkflowEngine(
            session: session,
            workflow: workflow,
            settingsStore: settingsStore,
            seedIntent: seedIdea
        )
        workflowEngine.start()
    }

    private func stop() {
        engineManager.workflowEngine(for: session.id)?.stop()
        syncProgress()
        try? sessionStore.transitionSession(session.id, to: .idle)
    }

    private func continueExecution() {
        guard let workflow else { return }
        do {
            try sessionStore.transitionSession(session.id, to: .running)
        } catch {
            return
        }
        ensureTerminalRunning(phaseIndex: session.currentPhaseIndex)
        if let workflowEngine = engineManager.workflowEngine(for: session.id) {
            workflowEngine.continueExecution()
        } else {
            let workflowEngine = engineManager.createWorkflowEngine(session: session, workflow: workflow, settingsStore: settingsStore)
            workflowEngine.start()
        }
    }

    private func restartFromCompleted() {
        guard let workflow else { return }

        var adjusted = session
        adjusted.completedStepIDs = adjusted.completedStepIDs.filter { $0 != "verify-qa" }
        adjusted.currentPhaseIndex = 2
        adjusted.currentStepIndex = 1

        sessionStore.updateSessionProgress(
            session.id,
            phaseIndex: adjusted.currentPhaseIndex,
            stepIndex: adjusted.currentStepIndex,
            completedStepIDs: adjusted.completedStepIDs
        )
        try? sessionStore.transitionSession(session.id, to: .idle)

        do {
            try sessionStore.transitionSession(session.id, to: .running)
        } catch {
            return
        }

        ensureTerminalRunning(phaseIndex: adjusted.currentPhaseIndex)
        let workflowEngine = engineManager.createWorkflowEngine(
            session: adjusted,
            workflow: workflow,
            settingsStore: settingsStore,
            seedIntent: seedIdea
        )
        workflowEngine.start()
    }

    private func runFromHere(phaseIndex: Int, stepIndex: Int) {
        guard let workflow else { return }
        ensureTerminalRunning(phaseIndex: phaseIndex)
        do {
            if session.state != .running {
                try sessionStore.transitionSession(session.id, to: .running)
            }
        } catch {
            return
        }
        if let workflowEngine {
            workflowEngine.runFromStep(phaseIndex: phaseIndex, stepIndex: stepIndex)
        } else {
            var adjustedSession = session
            adjustedSession.currentPhaseIndex = phaseIndex
            adjustedSession.currentStepIndex = stepIndex
            let workflowEngine = engineManager.createWorkflowEngine(
                session: adjustedSession,
                workflow: workflow,
                settingsStore: settingsStore
            )
            workflowEngine.runFromStep(phaseIndex: phaseIndex, stepIndex: stepIndex)
        }
    }

    private func ensureTerminalRunning(phaseIndex: Int? = nil) {
        // Boot the underlying terminal engine for every session, Ralph or not.
        // The previous `if session.workflowName.isEmpty` guard meant Ralph
        // sessions never spawned a CLI, so the WorkflowEngine's
        // injectPrompt calls went into the void.
        let tool = terminalToolIdentifier(forPhaseIndex: phaseIndex)
        let engine = engineManager.engine(for: session.id, tool: tool)
        if engine.engineState == .idle {
            try? engine.start(
                workingDirectory: session.workingDirectory,
                tool: tool
            )
        }
        engineManager.configureResolver(for: session)
    }

    private func terminalToolIdentifier(forPhaseIndex phaseIndex: Int?) -> String {
        guard let phaseIndex, let workflow, phaseIndex < workflow.phases.count else {
            return engineManager.defaultAgent
        }
        switch workflow.phases[phaseIndex].name.lowercased() {
        case "plan":
            return ProcessRunnerFactory.toolIdentifier(for: settingsStore.settings.planCLI)
        case "verify":
            return ProcessRunnerFactory.toolIdentifier(for: settingsStore.settings.verifyCLI)
        default:
            return engineManager.defaultAgent
        }
    }

    private func handleExecutionStateChange(_ newState: ExecutionState?) {
        guard let newState else { return }
        switch newState {
        case .paused:
            try? sessionStore.transitionSession(session.id, to: .paused)
        case .completed:
            syncProgress()
            try? sessionStore.transitionSession(session.id, to: .completed)
        case .stalled:
            syncProgress()
            try? sessionStore.transitionSession(session.id, to: .stalled)
        case .executing, .idle:
            break
        }
    }

    private func syncProgress() {
        guard let workflowEngine else { return }
        sessionStore.updateSessionProgress(
            session.id,
            phaseIndex: workflowEngine.currentPhaseIndex,
            stepIndex: workflowEngine.currentStepIndex,
            completedStepIDs: workflowEngine.completedStepIDs
        )
    }
}

extension SessionDetailView where Header == EmptyView {
    init(session: Session) {
        self.init(session: session) { EmptyView() }
    }
}

/// Walks up the NSView hierarchy from its anchor to find the nearest NSTabView
/// and sets toolTip on each NSTabViewItem in order.
private struct TabTooltipSetter: NSViewRepresentable {
    let tooltips: [String]

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var current: NSView? = nsView
            while let v = current {
                if let tabView = v as? NSTabView {
                    for (item, tip) in zip(tabView.tabViewItems, tooltips) {
                        item.toolTip = tip
                    }
                    return
                }
                current = v.superview
            }
        }
    }
}

struct MissingSessionDetailView: View {
    let entry: SessionRegistryEntry

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Working Directory Not Found")
                .font(.title3)
                .fontWeight(.medium)
            Text((entry.workingDirectory as NSString).abbreviatingWithTildeInPath)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { } label: {
                    Image(systemName: "play.fill")
                }
                .disabled(true)
                .help("Working directory not found — Relocate to restore.")
            }
        }
    }
}
