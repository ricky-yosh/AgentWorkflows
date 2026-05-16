import Foundation

/// Composite pure-function module that produces a unified Presence Report
/// covering the app's launch preconditions: required Skill installations.
///
/// Read-only: never mutates user settings, skills files, or UserDefaults.
/// Consumers use the report to drive the launch Presence Banner and the
/// Preferences Prerequisites pane.
///
/// Skills checking (probing each target-specific installed skill path) is the
/// module's primary responsibility.
enum PresenceChecker {

    /// The Skills Ralph needs; adding another is a Swift code change
    /// (see PRD "Further Notes"). Order is the display order in the banner.
    static let requiredSkills: [String] = [
        "grill-with-docs",
        "to-prd",
        "to-tasks",
        "ralph",
        "qa",
    ]

    struct MissingSkill: Equatable {
        let name: String
        let directory: URL
    }

    struct SkillInstallRoot {
        let target: SkillTarget
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
            let target = SkillTarget.allCases.first { $0.directory.path == dir.path }
            for name in requiredSkills where !skillPresent(in: dir, name: name, target: target) {
                missing.append(MissingSkill(name: name, directory: dir))
            }
        }
        return Report(missingSkillsByDirectory: missing)
    }

    static func check(
        skillTargets: [SkillTarget],
        globalSettingsPath: URL?,
        projectSettingsPath: URL?
    ) -> Report {
        _ = globalSettingsPath
        _ = projectSettingsPath
        let roots = skillTargets.map { SkillInstallRoot(target: $0, directory: $0.directory) }
        return check(skillInstallRoots: roots)
    }

    static func check(skillInstallRoots: [SkillInstallRoot]) -> Report {
        var missing: [MissingSkill] = []
        for root in skillInstallRoots {
            for name in requiredSkills where !skillPresent(in: root.directory, name: name, target: root.target) {
                missing.append(MissingSkill(name: name, directory: root.directory))
            }
        }
        return Report(missingSkillsByDirectory: missing)
    }

    private static func skillPresent(in skillsDirectory: URL, name: String, target: SkillTarget?) -> Bool {
        let skillFile: URL
        if let target {
            skillFile = SkillClassifier.installedSkillFileURL(
                skillsDirectory: skillsDirectory,
                skillName: name,
                target: target
            )
        } else {
            skillFile = skillsDirectory
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("SKILL.md")
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: skillFile.path,
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }
}
