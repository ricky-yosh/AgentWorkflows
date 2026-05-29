import SwiftUI

private struct AppCommands: Commands {
    @FocusedValue(\.isSessionSelected) private var isSessionSelected: Bool?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                NotificationCenter.default.post(name: .awShowNewSession, object: nil)
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("New Session in Same Folder") {
                NotificationCenter.default.post(name: .awNewSessionSameFolder, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(isSessionSelected != true)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Terminal") {
                NotificationCenter.default.post(name: .awToggleTerminal, object: nil)
            }
            .keyboardShortcut("\\", modifiers: .command)
            .disabled(isSessionSelected != true)

            Button("Next Session") {
                NotificationCenter.default.post(name: .awCycleSessionForward, object: nil)
            }
            .keyboardShortcut("\t", modifiers: .control)

            Button("Previous Session") {
                NotificationCenter.default.post(name: .awCycleSessionBackward, object: nil)
            }
            .keyboardShortcut("\t", modifiers: [.control, .shift])
        }

        CommandMenu("Session") {
            Button("Play/Pause Session") {
                NotificationCenter.default.post(name: .awSessionTogglePlayback, object: nil)
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(isSessionSelected != true)

            Button("Mark Step Complete") {
                NotificationCenter.default.post(name: .awSessionMarkStepComplete, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(isSessionSelected != true)

            Divider()

            Button("Open in Finder") {
                NotificationCenter.default.post(name: .awSessionOpenInFinder, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(isSessionSelected != true)

            Button("Open in Editor") {
                NotificationCenter.default.post(name: .awSessionOpenInEditor, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(isSessionSelected != true)

            Button("Open in Terminal") {
                NotificationCenter.default.post(name: .awSessionOpenInTerminal, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(isSessionSelected != true)

            Button("Open in Diff Viewer") {
                NotificationCenter.default.post(name: .awSessionOpenInDiffViewer, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(isSessionSelected != true)

            Divider()

            Button("Copy Session Path") {
                NotificationCenter.default.post(name: .awSessionCopyPath, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(isSessionSelected != true)

            Button("Copy Cache Path") {
                NotificationCenter.default.post(name: .awSessionCopyCachePath, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            .disabled(isSessionSelected != true)

            Divider()

            Button("Rename…") {
                NotificationCenter.default.post(name: .awSessionRename, object: nil)
            }
            .disabled(isSessionSelected != true)

            Divider()

            Button("Delete Session") {
                NotificationCenter.default.post(name: .awSessionDelete, object: nil)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(isSessionSelected != true)
        }
    }
}

@main
struct AgentWorkflowsApp: App {
    @State private var sessionStore: SessionStore
    @State private var engineManager: EngineManager
    @State private var windowManager = WindowManager()
    @State private var settingsStore = SettingsStore()

    init() {
        // Disable AppKit's automatic window tabbing. Without this, AppKit
        // injects a "Show Tab Bar" item bound to Cmd+T into the Window menu,
        // which steals the shortcut from our New Session alias below.
        NSWindow.allowsAutomaticWindowTabbing = false

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let awRoot = appSupport.appendingPathComponent("AW")

        let sessionsDir = awRoot.appendingPathComponent("sessions")
        BootMigrator.runIfNeeded(legacySessionsDirectory: sessionsDir, defaults: .standard)
        try? fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let configRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("AW", isDirectory: true)
        MigrationCleaner.runIfNeeded(
            sessionsDirectory: sessionsDir,
            configDirectory: configRoot,
            defaults: .standard
        )
        MigrationCleaner.purgeStaleSignalFiles(
            registry: SessionRegistry(),
            reachability: .live
        )

        let em = EngineManager()

        _sessionStore = State(initialValue: SessionStore())
        _engineManager = State(initialValue: em)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(sessionStore)
                .environment(engineManager)
                .environment(windowManager)
                .environment(settingsStore)
                .frame(minWidth: 900, minHeight: 500)
        }
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            AppCommands()
        }

        SwiftUI.Settings {
            PreferencesView()
                .environment(settingsStore)
        }
    }
}
