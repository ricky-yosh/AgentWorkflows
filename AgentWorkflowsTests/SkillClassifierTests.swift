import CryptoKit
import Foundation
import Testing
@testable import AgentWorkflows

@Suite("SkillClassifier")
struct SkillClassifierTests {

    private func sha256(of string: String) -> String {
        let data = Data(string.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test func nilBytesClassifiesAsMissing() {
        let result = SkillClassifier.classify(bytesOnDisk: nil, currentHash: "any", priorHashes: [])
        #expect(result == .missing)
    }

    @Test func bytesMatchingCurrentHashClassifiesAsClean() {
        let content = "skill content"
        let hash = sha256(of: content)
        let data = Data(content.utf8)
        let result = SkillClassifier.classify(bytesOnDisk: data, currentHash: hash, priorHashes: [])
        #expect(result == .clean)
    }

    @Test func bytesMatchingPriorHashButNotCurrentClassifiesAsStale() {
        let oldContent = "old skill content"
        let oldHash = sha256(of: oldContent)
        let currentHash = sha256(of: "new skill content")
        let data = Data(oldContent.utf8)
        let result = SkillClassifier.classify(bytesOnDisk: data, currentHash: currentHash, priorHashes: [oldHash])
        #expect(result == .stale)
    }

    @Test func bytesMatchingNeitherClassifiesAsModified() {
        let currentHash = sha256(of: "bundled content")
        let priorHash = sha256(of: "old bundled content")
        let data = Data("user-edited content".utf8)
        let result = SkillClassifier.classify(bytesOnDisk: data, currentHash: currentHash, priorHashes: [priorHash])
        #expect(result == .modified)
    }

    @Test func bytesNotMatchingCurrentWithEmptyPriorHashesClassifiesAsModified() {
        let currentHash = sha256(of: "bundled content")
        let data = Data("user-edited content".utf8)
        // With no prior hashes, Stale is unreachable — non-matching bytes are always Modified.
        let result = SkillClassifier.classify(bytesOnDisk: data, currentHash: currentHash, priorHashes: [])
        #expect(result == .modified)
    }

    @Test func openCodeTargetUsesFlatSkillFilePath() {
        let root = URL(fileURLWithPath: "/tmp/opencode-skills", isDirectory: true)
        let path = SkillClassifier.installedSkillFileURL(
            skillsDirectory: root,
            skillName: "ralph",
            target: .openCode
        )

        #expect(path.path == "/tmp/opencode-skills/ralph.md")
    }

    @Test func nonOpenCodeTargetsUseDirectorySkillLayout() {
        let root = URL(fileURLWithPath: "/tmp/skills", isDirectory: true)
        let path = SkillClassifier.installedSkillFileURL(
            skillsDirectory: root,
            skillName: "ralph",
            target: .claude
        )

        #expect(path.path == "/tmp/skills/ralph/SKILL.md")
    }
}
