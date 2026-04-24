import Foundation

/// Routes prompt writes to the active AgentEngine, records the last dispatched
/// prompt per session for resend, and owns a SignalWatcher so callers can cancel
/// an in-flight watch via a single call.
final class PromptDispatcher {
    private var engine: AgentEngine?
    private let watcher: SignalWatcher
    private(set) var lastPrompt: String?

    /// Called when the watched Signal File appears. WorkflowEngine wires this
    /// to `handleStepCompletion`; LoopDriver wires it to `handleSignalFired`.
    var onSignalFired: (() -> Void)?

    init(watcher: SignalWatcher) {
        self.watcher = watcher
        watcher.onFired = { [weak self] in self?.onSignalFired?() }
    }

    /// Records `prompt`, cancels any prior watch, starts watching `signalFilePath`,
    /// then injects the prompt into `engine`. The engine is retained for `resend()`.
    func dispatch(_ prompt: String, to engine: AgentEngine, signalFilePath: String) {
        self.engine = engine
        lastPrompt = prompt
        cancelWatcher()
        watcher.startWatching(signalFilePath: signalFilePath)
        engine.injectPrompt(prompt)
    }

    /// Re-injects the last dispatched prompt into the retained engine without
    /// touching the Signal File watcher. Used by Run From Here to replay the
    /// current step without terminating the Agent Session.
    func resend() {
        guard let p = lastPrompt, let e = engine else { return }
        e.injectPrompt(p)
    }

    /// Cancels any in-flight Signal File watch. Safe to call when idle.
    func cancelWatcher() {
        watcher.stopWatching()
    }
}
