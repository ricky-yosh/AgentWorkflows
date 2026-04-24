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
}
