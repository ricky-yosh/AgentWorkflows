import Foundation

/// Routes prompt writes to the active AgentEngine, records the last dispatched
/// prompt per session for resend.
final class PromptDispatcher {
    private var engine: AgentEngine?
    private(set) var lastPrompt: String?

    init() {}

    /// Records `prompt` and injects it into `engine`. The engine is retained for `resend()`.
    func dispatch(_ prompt: String, to engine: AgentEngine) {
        self.engine = engine
        lastPrompt = prompt
        engine.injectPrompt(prompt)
    }

    /// Re-injects the last dispatched prompt into the retained engine.
    /// Used by Run From Here to replay the current step without terminating the Agent Session.
    func resend() {
        guard let p = lastPrompt, let e = engine else { return }
        e.injectPrompt(p)
    }

    /// No-op. Retained for call-site compatibility with WorkflowEngine.
    func cancelWatcher() {}
}
