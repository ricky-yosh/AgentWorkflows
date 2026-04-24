import Foundation

/// One-shot wipe of the legacy Application Support per-session storage layout.
///
/// Before the in-repo Session Directory design, each Session's files lived under
/// `~/Library/Application Support/AW/sessions/<UUID>/`. That layout is
/// incompatible with the new in-repo layout and must be cleared on first launch
/// so SessionStore starts with a clean slate.
///
/// Idempotent via a `UserDefaults` flag: the first call removes the legacy
/// directory and sets the flag; every subsequent call returns immediately.
enum BootMigrator {

    /// UserDefaults key that gates the one-shot wipe.
    static let completionFlagKey = "AWSessionStorageWipeComplete_v1"

    /// Deletes `legacySessionsDirectory` on first call, then becomes a no-op.
    ///
    /// - Parameters:
    ///   - legacySessionsDirectory: `~/Library/Application Support/AW/sessions/`
    ///     — the directory to remove entirely. A missing directory is silently
    ///     treated as already wiped; the flag is still set.
    ///   - defaults: Injected `UserDefaults` instance so tests use a volatile
    ///     suite instead of polluting the shared standard domain.
    static func runIfNeeded(
        legacySessionsDirectory: URL,
        defaults: UserDefaults
    ) {
        guard defaults.bool(forKey: completionFlagKey) == false else { return }

        let fm = FileManager.default
        if fm.fileExists(atPath: legacySessionsDirectory.path) {
            try? fm.removeItem(at: legacySessionsDirectory)
        }

        defaults.set(true, forKey: completionFlagKey)
    }
}
