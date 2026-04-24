import AppKit
import Foundation
import Observation
import SwiftTerm

@Observable
final class TerminalEngine: AgentEngine {
    private(set) var engineState: EngineState = .idle
    let terminalView: LocalProcessTerminalView
    var templateResolver: TemplateResolver?
    var toolDefinition: CLIToolDefinition?
    var onStepComplete: (() -> Void)?  // unused by CLI engine — signal file used instead
    var onProcessExit: (() -> Void)?
    var onProcessReady: (() -> Void)?
    private let writeQueue = DispatchQueue(label: "aw.terminal.write-queue")
    private var processReady = false
    private var pendingPrompt: String?
    private var readinessTimer: DispatchWorkItem?

    init() {
        let view = LocalProcessTerminalView(frame: .zero)
        self.terminalView = view
        // Delegate set after init since self isn't available in property initializers
        view.processDelegate = self
    }

    func start(workingDirectory: String, tool: String) throws {
        guard engineState != .running else { return }
        processReady = false
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

        // Fallback: if no delegate signal fires within 5 seconds, consider
        // the process ready and flush any queued prompt.
        let timer = DispatchWorkItem { [weak self] in
            self?.markReady()
        }
        readinessTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timer)
    }

    func injectPrompt(_ text: String) {
        guard engineState == .running else { return }
        let resolved = templateResolver?.resolve(text) ?? text
        let normalized = TerminalEngine.normalizeTerminator(resolved)
        if processReady {
            sendToProcess(normalized)
        } else {
            pendingPrompt = normalized
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

    /// Strips any trailing newline/CR and appends \r so the PTY submits the
    /// prompt on arrival. Internal \n characters are left for sendToProcess
    /// to handle via its \n→\r conversion.
    static func normalizeTerminator(_ text: String) -> String {
        var s = text
        while s.hasSuffix("\n") || s.hasSuffix("\r") {
            s = String(s.dropLast())
        }
        return s + "\r"
    }

    /// Returns the UTF-8 bytes that sendToProcess will write to the PTY for
    /// `text`. Applies the same \n→\r conversion used in production so tests
    /// can assert exact byte sequences without a real process.
    static func bytesForPTY(_ text: String) -> [UInt8] {
        Array(text.replacingOccurrences(of: "\n", with: "\r").utf8)
    }

    /// Called when the process signals it's ready (terminal title set, directory
    /// update received, or timeout). Flushes any queued prompt.
    private func markReady() {
        guard !processReady, engineState == .running else { return }
        processReady = true
        readinessTimer?.cancel()
        readinessTimer = nil
        onProcessReady?()
        if let prompt = pendingPrompt {
            pendingPrompt = nil
            sendToProcess(prompt)
        }
    }

    private func sendToProcess(_ text: String) {
        writeQueue.async { [weak self] in
            guard let process = self?.terminalView.process else { return }
            // Replace \n with \r — in a PTY, Enter sends CR (0x0D).
            // The line discipline converts CR→LF for the process.
            let data = Array(text.replacingOccurrences(of: "\n", with: "\r").utf8)
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
        readinessTimer?.cancel()
        readinessTimer = nil
        processReady = false
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
            self?.engineState = .terminated(exitCode: exitCode)
            self?.onProcessExit?()
        }
    }
}
