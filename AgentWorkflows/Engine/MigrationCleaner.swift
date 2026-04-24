import Foundation

/// One-shot cleanup that deletes on-disk artifacts from pre-Ralph versions of
/// AgentWorkflows. Earlier builds persisted Sessions, user-authored Workflows
/// under `~/.config/AW/workflows`, Block definitions under `~/.config/AW/blocks`,
/// and a handful of Workflow-related keys in `UserDefaults`. The Ralph-only
/// rewrite inlines the Workflow and has no editor, so every one of those
/// artifacts is dead — but a user upgrading in place will still have them on
/// disk and they must be cleared before `SessionStore` enumerates the Sessions
/// directory (old Session formats would otherwise attempt to decode and
/// crash).
///
/// Idempotent via a single `UserDefaults` flag: the first call does the work
/// and sets the flag; every subsequent call returns immediately.
enum MigrationCleaner {

    /// Key read and written to track whether the one-shot cleanup has run.
    static let completionFlagKey = "AW.migration.v1.complete"

    /// Workflow-related `UserDefaults` keys that the Ralph rewrite retired.
    /// Listed explicitly so an accidental rename of a still-live key (e.g.
    /// `defaultAgent`) doesn't sweep it away.
    static let staleUserDefaultsKeys: [String] = [
        "digestProvider",
        "digestPromptTemplate",
        "claudeAPIKey",
    ]

    /// Runs the cleanup once per `UserDefaults` domain.
    ///
    /// - Parameters:
    ///   - sessionsDirectory: The directory whose *contents* are wiped. The
    ///     directory itself is preserved so the caller can proceed to create
    ///     new Sessions in place.
    ///   - configDirectory: The `~/.config/AW` root whose `workflows/` and
    ///     `blocks/` subtrees are wiped if present. The root itself is left
    ///     alone — other subtrees belong to unrelated features.
    ///   - defaults: The `UserDefaults` instance to read the completion flag
    ///     from and to strip stale keys from. Injected so tests can use a
    ///     volatile suite instead of the shared standard domain.
    static func runIfNeeded(
        sessionsDirectory: URL,
        configDirectory: URL,
        defaults: UserDefaults
    ) {
        guard defaults.bool(forKey: completionFlagKey) == false else { return }

        wipeDirectoryContents(at: sessionsDirectory)
        removeSubtree(at: configDirectory.appendingPathComponent("workflows"))
        removeSubtree(at: configDirectory.appendingPathComponent("blocks"))
        for key in staleUserDefaultsKeys {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: completionFlagKey)
    }

    /// Removes every entry inside `url` but leaves `url` itself in place. A
    /// missing directory is a no-op — it's indistinguishable from a
    /// successful prior wipe.
    private static func wipeDirectoryContents(at url: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }
        for entry in entries {
            try? fm.removeItem(at: entry)
        }
    }

    /// Removes `url` (file or directory) if it exists. Missing is a no-op.
    private static func removeSubtree(at url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        try? fm.removeItem(at: url)
    }

    /// Purges stale Signal Files from every reachable Session directory at app start.
    ///
    /// Signal Files mark a completed Step. If the app crashes while a Loop is
    /// mid-flight, leftover Signal Files would cause the engine to falsely
    /// advance the first Step on the next launch. This sweep runs
    /// unconditionally every launch — it is NOT gated by `completionFlagKey`.
    ///
    /// - Parameters:
    ///   - registry: The session registry to read entries from.
    ///   - reachability: Used to classify whether each entry's Working Directory exists.
    static func purgeStaleSignalFiles(registry: SessionRegistry, reachability: SessionReachability) {
        guard let entries = try? registry.load() else { return }
        let fm = FileManager.default
        for entry in entries where reachability.classify(entry: entry) == .reachable {
            let workingDir = URL(fileURLWithPath: entry.workingDirectory)
            let signalFile = SessionDirectoryLayout.signalFileURL(
                workingDirectory: workingDir,
                sessionID: entry.id
            )
            if fm.fileExists(atPath: signalFile.path) {
                try? fm.removeItem(at: signalFile)
            }
        }
    }
}
