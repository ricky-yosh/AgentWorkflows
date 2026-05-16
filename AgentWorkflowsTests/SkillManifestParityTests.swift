import Foundation
import Testing
@testable import AgentWorkflows

@Suite("SkillManifestParity")
struct SkillManifestParityTests {

    @Test func manifestNamesMatchRequiredSkills() throws {
        let contents = try SkillBundleReader.read(from: .main)
        let manifestNames = Set(contents.manifest.map(\.name))
        let requiredNames = Set(PresenceChecker.requiredSkills)

        let extraInManifest = manifestNames.subtracting(requiredNames)
        let extraInRequired = requiredNames.subtracting(manifestNames)

        #expect(extraInManifest.isEmpty, "Manifest has skills not in requiredSkills: \(extraInManifest.sorted())")
        #expect(extraInRequired.isEmpty, "requiredSkills has skills not in manifest: \(extraInRequired.sorted())")
    }

    @Test func requiredSkillsResolveForAllSkillTargets() {
        let roots: [SkillTarget: URL] = [
            .claude: URL(fileURLWithPath: "/tmp/claude-skills", isDirectory: true),
            .codex: URL(fileURLWithPath: "/tmp/codex-skills", isDirectory: true),
            .pi: URL(fileURLWithPath: "/tmp/pi-skills", isDirectory: true),
            .openCode: URL(fileURLWithPath: "/tmp/opencode-skills", isDirectory: true),
        ]

        for target in SkillTarget.allCases {
            guard let root = roots[target] else {
                Issue.record("Missing temp root for target \(target.rawValue)")
                continue
            }
            for name in PresenceChecker.requiredSkills {
                let path = SkillClassifier.installedSkillFileURL(
                    skillsDirectory: root,
                    skillName: name,
                    target: target
                )
                switch target {
                case .openCode:
                    #expect(path.path == root.appendingPathComponent("\(name).md").path)
                case .claude, .codex, .pi:
                    #expect(path.path == root.appendingPathComponent("\(name)/SKILL.md").path)
                }
            }
        }
    }
}
