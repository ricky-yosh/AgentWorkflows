import Foundation

/// The reasoning budget passed to `claude -p --effort` for each Iteration.
/// Resolution rules live exclusively here — no caller re-implements them.
enum Effort: String {
    case low
    case medium
    case high

    /// Resolves a raw string from the Tasks File to an Effort Level.
    ///
    /// - `"low"`, `"medium"`, `"high"` → the matching case.
    /// - `"xhigh"`, `"max"` → `.high` (Effort Ceiling clamp).
    /// - `nil`, empty, whitespace-only, or any other value → `.medium` (Effort Default).
    init(raw: String?) {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            self = .medium
            return
        }
        switch raw {
        case "xhigh", "max":
            self = .high
        default:
            self = Effort(rawValue: raw) ?? .medium
        }
    }
}
