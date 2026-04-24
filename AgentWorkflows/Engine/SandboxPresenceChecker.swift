import Foundation

/// Pure-function module that reports whether Claude Code's OS-level Sandbox is
/// enabled in any readable Claude settings file. Never writes to any file;
/// consumers use the result to surface a non-blocking warning.
///
/// The module is deep: callers pass explicit paths (typically the user-global
/// `~/.claude/settings.json` and a project-local `<project>/.claude/settings.local.json`),
/// and the function handles missing files and malformed JSON without throwing.
///
/// **Distinction from `PresenceChecker`:** This module is intentionally narrow —
/// it knows nothing about Skills. Its only job is reading JSON settings files to
/// detect the `sandbox.enabled` flag. `PresenceChecker` is the primary consumer:
/// it delegates sandbox detection here and adds skill-installation checking on top.
enum SandboxPresenceChecker {

    struct Result: Equatable {
        let sandboxEnabled: Bool
        /// Path of the settings file that supplied `sandbox.enabled: true`.
        /// `nil` when no readable file reported the Sandbox as enabled.
        let source: String?
    }

    /// Check the supplied settings files for `sandbox.enabled: true`.
    ///
    /// Project-local is consulted before user-global so that its path is
    /// reported as the `source` when both files enable the Sandbox — matching
    /// Claude Code's own precedence (project-local overrides user-global).
    ///
    /// - Parameters:
    ///   - globalSettingsPath: Absolute URL of `~/.claude/settings.json`, or
    ///     `nil` when the caller has no global file to consult.
    ///   - projectSettingsPath: Absolute URL of the project's
    ///     `.claude/settings.local.json`, or `nil` when the caller has no
    ///     project file to consult.
    static func check(
        globalSettingsPath: URL?,
        projectSettingsPath: URL?
    ) -> Result {
        let ordered: [URL] = [projectSettingsPath, globalSettingsPath].compactMap { $0 }
        for url in ordered {
            if readSandboxEnabled(at: url) {
                return Result(sandboxEnabled: true, source: url.path)
            }
        }
        return Result(sandboxEnabled: false, source: nil)
    }

    /// Reads a single settings file and returns whether `sandbox.enabled` is
    /// exactly `true`. Missing files, unreadable files, and malformed JSON all
    /// yield `false` — the warning Banner exists specifically to surface
    /// "Sandbox cannot be confirmed", so any ambiguity must degrade safely.
    private static func readSandboxEnabled(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        guard let sandbox = root["sandbox"] as? [String: Any] else { return false }
        return (sandbox["enabled"] as? Bool) == true
    }
}
