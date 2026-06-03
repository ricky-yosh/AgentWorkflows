import SwiftUI

/// Session detail layout: terminal as permanent left pane, tabs on the right.
struct SessionDetailView<Header: View>: View {
    let session: Session
    @ViewBuilder let headerContent: Header

    @Environment(SessionStore.self) private var sessionStore
    @Environment(EngineManager.self) private var engineManager
    @Environment(SettingsStore.self) private var settingsStore

    @State private var terminalDividerState = TerminalDividerState()
    @State private var phaseExpansion: [AnyHashable: Bool] = [:]
    @State private var workflow: Workflow?

    /// Seed intent collected from the pre-Play modal. Held in memory for
    /// the session's lifetime — re-Play after stop/complete reuses the
    /// same seed without re-prompting.
    @State private var seedIdea: String?
    @State private var seedPromptPresented = false
    private enum SessionTab: Hashable {
        case iterations, files, diff, log, workflow

        var rawValue: String {
            switch self {
            case .iterations: return "iterations"
            case .files: return "files"
            case .diff: return "diff"
            case .log: return "log"
            case .workflow: return "workflow"
            }
        }

        init(rawValue: String) {
            switch rawValue {
            case "files": self = .files
            case "diff": self = .diff
            case "log": self = .log
            case "workflow": self = .workflow
            default: self = .iterations
            }
        }
    }

    private var selectedTab: SessionTab {
        get { SessionTab(rawValue: engineManager.selectedDetailTab(for: session.id)) }
        nonmutating set { engineManager.setSelectedDetailTab(newValue.rawValue, for: session.id) }
    }

    private var selectedTabBinding: Binding<SessionTab> {
        Binding(
            get: { selectedTab },
            set: {
                selectedTab = $0
                focusTerminal()
            }
        )
    }

    private var workflowEngine: WorkflowEngine? {
        engineManager.workflowEngine(for: session.id)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                headerContent
                HSplitView {
                    if !terminalDividerState.collapsed {
                        terminalPane
                            .frame(
                                minWidth: TerminalDividerState.minimumWidth,
                                maxWidth: terminalDividerState.fullWidth
                                    ? .infinity
                                    : geometry.size.width * TerminalDividerState.maxWindowFraction
                            )
                            .background(SplitViewBridge(state: terminalDividerState))
                    }
                    if !terminalDividerState.fullWidth {
                        tabPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: selectedTabBinding) {
                    Image(systemName: "repeat")
                        .accessibilityLabel("Iterations")
                        .tag(SessionTab.iterations)
                    Image(systemName: "folder")
                        .accessibilityLabel("Files")
                        .tag(SessionTab.files)
                    Image(systemName: "plusminus")
                        .accessibilityLabel("Diff")
                        .tag(SessionTab.diff)
                    Image(systemName: "list.bullet.rectangle")
                        .accessibilityLabel("Log")
                        .tag(SessionTab.log)
                    Image(systemName: "arrow.triangle.branch")
                        .accessibilityLabel("Workflow")
                        .tag(SessionTab.workflow)
                }
                .pickerStyle(.segmented)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        terminalDividerState.toggleFullWidth()
                    }
                } label: {
                    Image(systemName: terminalDividerState.fullWidth
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                }
                .help(terminalDividerState.fullWidth ? "Exit Full Width" : "Full Width Terminal")
                playStopButton
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .awToggleTerminal)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                terminalDividerState.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .awToggleFullWidthTerminal)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                terminalDividerState.toggleFullWidth()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .awSessionTogglePlayback)) { _ in
            togglePlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: .awSelectSessionTab)) { notification in
            if let rawValue = notification.object as? String {
                selectedTab = SessionTab(rawValue: rawValue)
                focusTerminal()
            }
        }
            .task(id: session.id) {
                phaseExpansion = [:]
                seedIdea = nil
                seedPromptPresented = false
                workflow = nil
                loadWorkflow()
                primeTaskCounts()
                focusTerminal()
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
    private var terminalPane: some View {
        TerminalHost(session: session)
    }

    @ViewBuilder
    private var tabPane: some View {
        VStack(spacing: 0) {
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
    }

    @ViewBuilder
    private var tabbedBody: some View {
        tabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            IterationsView(
                sessionID: session.id,
                tasksFileURL: SessionDirectoryLayout.tasksFileURL(
                    workingDirectory: URL(fileURLWithPath: session.workingDirectory),
                    sessionID: session.id
                )
            )
            .opacity(selectedTab == .iterations ? 1 : 0)
            .allowsHitTesting(selectedTab == .iterations)

            DocsView(session: session, terminalCollapsed: terminalDividerState.collapsed)
                .opacity(selectedTab == .files ? 1 : 0)
                .allowsHitTesting(selectedTab == .files)

            SessionDiffView(session: session)
                .opacity(selectedTab == .diff ? 1 : 0)
                .allowsHitTesting(selectedTab == .diff)

            ExecutionLogTabView(sessionID: session.id)
                .opacity(selectedTab == .log ? 1 : 0)
                .allowsHitTesting(selectedTab == .log)

            WorkflowTab(
                session: session,
                workflow: workflow,
                workflowEngine: workflowEngine,
                phaseExpansion: $phaseExpansion,
                onRunFromHere: { runFromHere(phaseIndex: $0, stepIndex: $1) }
            )
            .opacity(selectedTab == .workflow ? 1 : 0)
            .allowsHitTesting(selectedTab == .workflow)
        }
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
        let sessionID = session.id
        let isWorkflowSession = !session.workflowName.isEmpty
        let em = engineManager
        let settings = settingsStore
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Mirror TerminalHost.currentEngine resolution so we focus the visible terminal,
            // not a different (possibly hidden) engine.
            let activeTools = em.activeTools(for: sessionID)
            let activeTool: String
            if let last = activeTools.last {
                activeTool = last
            } else if !isWorkflowSession {
                let idlePreset = em.idleToolOverride(for: sessionID) ?? settings.settings.buildCLI
                activeTool = ProcessRunnerFactory.toolIdentifier(for: idlePreset)
            } else {
                return  // workflow session with no active tool — terminal not yet visible
            }
            let terminalView = em.engine(for: sessionID, tool: activeTool).terminalView
            guard let window = terminalView.window else { return }
            _ = window.makeFirstResponder(nil)
            _ = window.makeFirstResponder(terminalView)
        }
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
            return ProcessRunnerFactory.toolIdentifier(for: settingsStore.settings.buildCLI)
        }
        switch workflow.phases[phaseIndex].name.lowercased() {
        case "plan":
            return ProcessRunnerFactory.toolIdentifier(for: settingsStore.settings.planCLI)
        case "verify":
            return ProcessRunnerFactory.toolIdentifier(for: settingsStore.settings.verifyCLI)
        default:
            return ProcessRunnerFactory.toolIdentifier(for: settingsStore.settings.buildCLI)
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
