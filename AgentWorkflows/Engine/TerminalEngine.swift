import AppKit
import Foundation
import Observation
import SwiftTerm

@Observable
final class TerminalEngine: AgentEngine {
    private(set) var engineState: EngineState = .idle
    let terminalView: LocalProcessTerminalView
    var templateResolver: TemplateResolver?
    var toolDefinition: CLIToolDefinition? {
        didSet {
            configureShiftEnterForTool()
        }
    }
    var onStepComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?
    var onProcessReady: (() -> Void)?
    var onDebugLog: ((String) -> Void)?
    private let writeQueue = DispatchQueue(label: "aw.terminal.write-queue")
    private var processReady = false
    private var pendingPrompt: String?
    private var readinessTimer: DispatchWorkItem?
    private var readyViaTimeout = false

    init() {
        let view = ScrollTrackingTerminalView(frame: .zero)
        self.terminalView = view
        // Delegate set after init since self isn't available in property initializers
        view.processDelegate = self
        TerminalEngine.applyTheme(to: view)
    }

    private static func applyTheme(to view: LocalProcessTerminalView) {
        view.nativeBackgroundColor = NSColor(srgbRed: 0x28/255, green: 0x2C/255, blue: 0x34/255, alpha: 1)
        view.nativeForegroundColor = NSColor(srgbRed: 0xAB/255, green: 0xB2/255, blue: 0xBF/255, alpha: 1)
        func c(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Color {
            Color(red: UInt16(r) * 257, green: UInt16(g) * 257, blue: UInt16(b) * 257)
        }
        view.installColors([
            c(0x3F, 0x44, 0x51), c(0xE0, 0x6C, 0x75), c(0x98, 0xC3, 0x79), c(0xE5, 0xC0, 0x7B),
            c(0x61, 0xAF, 0xEF), c(0xC6, 0x78, 0xDD), c(0x56, 0xB6, 0xC2), c(0xAB, 0xB2, 0xBF),
            c(0x4F, 0x56, 0x66), c(0xE0, 0x6C, 0x75), c(0x98, 0xC3, 0x79), c(0xE5, 0xC0, 0x7B),
            c(0x61, 0xAF, 0xEF), c(0xC6, 0x78, 0xDD), c(0x56, 0xB6, 0xC2), c(0xFF, 0xFF, 0xFF),
        ])
    }

    private func debugLog(_ msg: String) {
        let cb = onDebugLog
        DispatchQueue.main.async { cb?(msg) }
    }

    func start(workingDirectory: String, tool: String) throws {
        guard engineState != .running else { return }
        processReady = false
        readyViaTimeout = false
        pendingPrompt = nil
        readinessTimer?.cancel()

        let command = toolDefinition?.command ?? "/bin/zsh"
        // Only default to ["-l"] (login shell) when there's no tool definition at all.
        // A tool with nil/empty defaultArgs should launch with no extra flags.
        let args = toolDefinition != nil ? (toolDefinition?.defaultArgs ?? []) : ["-l"]
        let env = TerminalEngine.childEnvironment()

        if command.hasPrefix("/") {
            // Full path — run directly
            terminalView.startProcess(
                executable: command,
                args: args,
                environment: env,
                execName: nil,
                currentDirectory: workingDirectory
            )
        } else {
            // Bare command (e.g. "claude") — run through a login interactive
            // shell so .zshrc is sourced and the user's full PATH is available.
            // `exec` replaces zsh with the target process so the PTY connects
            // directly to it.
            let quoted = ([command] + (args)).map { arg in
                "'\(arg.replacingOccurrences(of: "'", with: "'\\''"))'"
            }.joined(separator: " ")
            terminalView.startProcess(
                executable: "/bin/zsh",
                args: ["-li", "-c", "exec \(quoted)"],
                environment: env,
                execName: nil,
                currentDirectory: workingDirectory
            )
        }
        engineState = .running
        let launchDesc = command.hasPrefix("/")
            ? "\(command) \(args.joined(separator: " "))"
            : "zsh -li -c exec \(command) \(args.joined(separator: " "))"
        debugLog("[engine/\(tool)] start — \(launchDesc)")

        // Fallback: if no delegate signal fires within 5 seconds, consider
        // the process ready and flush any queued prompt.
        let timer = DispatchWorkItem { [weak self] in
            self?.readyViaTimeout = true
            self?.markReady()
        }
        readinessTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timer)
    }

    func injectPrompt(_ text: String) {
        guard engineState == .running else { return }
        let resolved = templateResolver?.resolve(text) ?? text
        var stripped = resolved
        while stripped.hasSuffix("\n") || stripped.hasSuffix("\r") {
            stripped = String(stripped.dropLast())
        }
        // Bracketed paste: inject text into the input without auto-submitting.
        // The terminal app receives ESC[200~…ESC[201~ and treats contents literally,
        // so embedded newlines don't fire Enter. The user presses send manually.
        let pasted = "\u{1b}[200~\(stripped)\u{1b}[201~"
        if processReady {
            debugLog("[engine] inject \(stripped.count)ch — sent immediately")
            sendRaw(pasted)
        } else {
            debugLog("[engine] inject \(stripped.count)ch — queued (process not ready)")
            pendingPrompt = pasted
        }
    }

    /// OpenCode needs ESC+CR to work around charmbracelet/x/input #1505.
    /// Everything else uses CSI u (`ESC [ 13 ; 2 u`) which crossterm parses
    /// as Shift+Enter when the Kitty keyboard protocol is negotiated.
    private func configureShiftEnterForTool() {
        guard let view = terminalView as? ScrollTrackingTerminalView else {
            NSLog("[TerminalEngine] configureShiftEnterForTool: view is not ScrollTrackingTerminalView")
            return
        }
        let toolName = toolDefinition?.name ?? "nil"
        if toolName == "opencode" {
            view.tuiShiftEnterBytes = [0x1B, 0x0D]
            NSLog("[TerminalEngine] configureShiftEnterForTool: opencode → ESC+CR")
        } else {
            NSLog("[TerminalEngine] configureShiftEnterForTool: %@ → bracketed paste (default)", toolName)
        }
    }

    /// Environment for the PTY child. SwiftTerm's default (`environment: nil`)
    /// intentionally drops PATH, leaving the child shell to rebuild it from
    /// `.zshrc`. When PATH isn't fully reconstructed, `exec claude` fails —
    /// and because `-i` interactive mode keeps zsh alive on exec failure, the
    /// user sees a live zsh prompt instead of Claude. Mirror SubprocessRunner's
    /// pathPrefix so the headless and PTY paths agree on where to find CLIs.
    static func childEnvironment() -> [String] {
        let home = NSHomeDirectory()
        let pathPrefix = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"] ?? ""
        env["PATH"] = existing.isEmpty ? pathPrefix : "\(pathPrefix):\(existing)"
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }
    }

    /// Called when the process signals it's ready (terminal title set, directory
    /// update received, or timeout). Flushes any queued prompt.
    private func markReady() {
        guard !processReady, engineState == .running else { return }
        processReady = true
        readinessTimer?.cancel()
        readinessTimer = nil
        let via = readyViaTimeout ? "timeout fallback" : "delegate signal"
        if let prompt = pendingPrompt {
            debugLog("[engine] ready (\(via)) — flushing \(prompt.count)ch queued prompt")
        } else {
            debugLog("[engine] ready (\(via))")
        }
        onProcessReady?()
        if let prompt = pendingPrompt {
            pendingPrompt = nil
            sendRaw(prompt)
        }
    }

    private func sendRaw(_ text: String) {
        writeQueue.async { [weak self] in
            guard let process = self?.terminalView.process else { return }
            let data = Array(text.utf8)
            let chunkSize = 1024
            for offset in stride(from: 0, to: data.count, by: chunkSize) {
                let end = min(offset + chunkSize, data.count)
                let chunk = data[offset..<end]
                process.send(data: chunk)
                if end < data.count {
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }
        }
    }

    func terminate() {
        debugLog("[engine] terminate — state was \(engineState)")
        readinessTimer?.cancel()
        readinessTimer = nil
        processReady = false
        readyViaTimeout = false
        pendingPrompt = nil
        terminalView.terminate()
        engineState = .idle
    }
}

extension TerminalEngine: LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async { [weak self] in
            self?.markReady()
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.markReady()
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            let code = exitCode.map { "\($0)" } ?? "nil"
            self?.debugLog("[engine] process exited \(code)")
            self?.engineState = .terminated(exitCode: exitCode)
            self?.onProcessExit?()
        }
    }
}
