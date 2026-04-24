import Foundation

struct SkillManifestEntry: Codable, Equatable {
    let name: String
    let sha256: String
    let priorSha256s: [String]
}
