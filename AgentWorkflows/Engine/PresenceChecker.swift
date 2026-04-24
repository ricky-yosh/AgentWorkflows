import Foundation

/// Composite pure-function module that produces a unified Presence Report
/// covering the app's launch preconditions: required Skill installations.
///
/// Read-only: never mutates user settings, skills files, or UserDefaults.
/// Consumers use the report to drive the launch Presence Banner and the
/// Preferences Prerequisites pane.
///
/// Skills checking (probing `~/.claude/skills/<name>/SKILL.md`) is the module's
/// primary responsibility.
enum PresenceChecker {

    /// The Skills Ralph needs; adding a seventh is a Swift code change
    /// (see PRD "Further Notes"). Order is the display order in the banner.
    static let requiredSkills: [String] = [
        "ralph",
        "grill-me",
        "ubiquitous-language",
        "to-prd",
        "prd-to-tasks",
        "qa",
    ]

    struct MissingSkill: Equatable {
        let name: String
        let directory: URL
    }

    struct Report: Equatable {
        /// All (skill, directory) pairs where the skill file is absent.
        let missingSkillsByDirectory: [MissingSkill]

        var allSkillsPresent: Bool {
            missingSkillsByDirectory.isEmpty
        }

        /// Unique skill names that are missing in at least one configured directory.
        var missingSkills: [String] {
            var seen = Set<String>()
            return missingSkillsByDirectory
                .map(\.name)
                .filter { seen.insert($0).inserted }
        }
    }

    /// Probe Skill install locations across all configured CLI directories.
    ///
    /// - Parameters:
    ///   - skillsDirectories: All skill directories to check — one per unique CLI in use.
    ///     A skill is considered present in a directory when
    ///     `<dir>/<skillName>/SKILL.md` exists and is readable.
    static func check(
        skillsDirectories: [URL],
        globalSettingsPath: URL?,
        projectSettingsPath: URL?
    ) -> Report {
        _ = globalSettingsPath
        _ = projectSettingsPath
        var missing: [MissingSkill] = []
        for dir in skillsDirectories {
            for name in requiredSkills where !skillPresent(in: dir, name: name) {
                missing.append(MissingSkill(name: name, directory: dir))
            }
        }
        return Report(missingSkillsByDirectory: missing)
    }

    private static func skillPresent(in skillsDirectory: URL, name: String) -> Bool {
        let skillFile = skillsDirectory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("SKILL.md")
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: skillFile.path,
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }
}
