import Foundation

/// Pure-function module that appends the engine's Signal-file footer to a
/// Bundled prompt body at injection time. The footer tells the Agent to write
/// the Signal file at the per-Session path that WorkflowEngine's kqueue watcher
/// is listening on, so Bundled prompts don't carry hand-rolled completion
/// instructions and stay portable across Sessions.
enum PromptSignalFooterWrapper {

    enum WrapError: Error, Equatable, CustomStringConvertible {
        case emptyProgressPath
        case emptySessionId

        var description: String {
            switch self {
            case .emptyProgressPath:
                return "PromptSignalFooterWrapper: progressPath is empty; cannot build Signal-file footer."
            case .emptySessionId:
                return "PromptSignalFooterWrapper: sessionId is empty; cannot build Signal-file footer."
            }
        }
    }

    /// Append the Signal-file footer to `promptBody` for the given Session.
    ///
    /// - Parameters:
    ///   - promptBody: The Bundled prompt body, frontmatter stripped. Passed
    ///     through verbatim; may be empty (a footer-only prompt is degenerate
    ///     but not an error — the caller's bundled-resource installer is the
    ///     guard against missing prompts).
    ///   - progressPath: Absolute or workspace-relative path of the Session's
    ///     progress directory (the parent of the Signal file).
    ///   - sessionId: The Session's stable identifier; becomes the Signal
    ///     file's suffix so multiple Sessions in one workspace don't collide.
    /// - Returns: `promptBody` followed by a blank line and the footer.
    /// - Throws: `WrapError.emptyProgressPath` or `.emptySessionId` when those
    ///   inputs are empty — a silently broken footer would leave the engine
    ///   waiting forever on a Signal file the Agent was never told to write.
    static func wrap(
        promptBody: String,
        progressPath: String,
        sessionId: String
    ) throws -> String {
        guard !progressPath.isEmpty else { throw WrapError.emptyProgressPath }
        guard !sessionId.isEmpty else { throw WrapError.emptySessionId }

        let signalPath = "\(progressPath)/step-complete-\(sessionId)"
        let footer = """
        ---

        When this Step's work is complete, write an empty file at the path \
        below to signal the AgentWorkflows engine that the Step is done:

            \(signalPath)

        Do not write the Signal file before the Step's work is finished. \
        Writing it advances the Workflow.
        """

        if promptBody.isEmpty { return footer }
        let trimmed = promptBody.hasSuffix("\n") ? String(promptBody.dropLast()) : promptBody
        return "\(trimmed)\n\n\(footer)"
    }
}
