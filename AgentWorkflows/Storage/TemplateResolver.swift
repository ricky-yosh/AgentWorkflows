import Foundation

struct TemplateResolver {
    let sessionID: UUID

    /// Resolves `{progress-path}` and `{signal-path}` template variables in the given text.
    /// - `{progress-path}` → `.aw-cache/{sessionID}`
    /// - `{signal-path}` → `.aw-cache/{sessionID}/step-complete-{sessionID}`
    /// Other text (including unknown `{variables}`) passes through unchanged.
    func resolve(_ text: String) -> String {
        let progressPath = ".aw-cache/\(sessionID.uuidString)"
        let signalPath = "\(progressPath)/step-complete-\(sessionID.uuidString)"

        return text
            .replacingOccurrences(of: "{progress-path}", with: progressPath)
            .replacingOccurrences(of: "{signal-path}", with: signalPath)
    }
}
