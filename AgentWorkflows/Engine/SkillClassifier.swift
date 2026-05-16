import CryptoKit
import Foundation

enum SkillClassifier {

    enum State {
        case missing
        case clean
        case stale
        case modified
    }

    static func installedSkillFileURL(skillsDirectory: URL, skillName: String, target: SkillTarget) -> URL {
        switch target {
        case .openCode:
            return skillsDirectory.appendingPathComponent("\(skillName).md")
        case .claude, .codex, .pi:
            return skillsDirectory
                .appendingPathComponent(skillName)
                .appendingPathComponent("SKILL.md")
        }
    }

    static func classify(bytesOnDisk: Data?, currentHash: String, priorHashes: [String]) -> State {
        guard let data = bytesOnDisk else { return .missing }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if hash == currentHash { return .clean }
        if priorHashes.contains(hash) { return .stale }
        return .modified
    }
}
