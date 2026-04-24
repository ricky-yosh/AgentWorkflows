import Foundation

enum EngineState: Equatable {
    case idle
    case running
    case terminated(exitCode: Int32?)
}

protocol AgentEngine: AnyObject {
    var engineState: EngineState { get }
    /// Set before calling injectPrompt. SDK engines fire this instead of writing a signal file.
    /// CLI engines ignore it — they rely on signal file watching.
    var onStepComplete: (() -> Void)? { get set }
    /// Fired when the underlying process exits (Ctrl+C, crash, etc.).
    /// WorkflowEngine uses this to detect mid-step termination and pause.
    var onProcessExit: (() -> Void)? { get set }
    /// Fired once when the process signals it is ready to receive input.
    /// TerminalRestartCoordinator sets this to detect post-restart readiness.
    var onProcessReady: (() -> Void)? { get set }
    func start(workingDirectory: String, tool: String) throws
    func injectPrompt(_ text: String)
    func terminate()
}
