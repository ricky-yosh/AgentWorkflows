import Foundation
import Testing
@testable import AgentWorkflows

@Suite("SkillBundleReader")
struct SkillBundleReaderTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-bundle-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeManifest(_ entries: [[String: Any]], to dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("skills-manifest.json")
        let data = try JSONSerialization.data(withJSONObject: entries)
        try data.write(to: url)
        return url
    }

    private func makeManifestEntry(name: String, sha256: String = "abc123", priorSha256s: [String] = []) -> [String: Any] {
        ["name": name, "sha256": sha256, "priorSha256s": priorSha256s]
    }

    @Test func returnsSkillsAndManifestForValidInput() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = try writeManifest([
            makeManifestEntry(name: "ralph", sha256: "aaa"),
            makeManifestEntry(name: "grill-with-docs", sha256: "bbb", priorSha256s: ["old"]),
        ], to: root)
        let skillsBase = root.appendingPathComponent("Skills", isDirectory: true)

        let contents = try SkillBundleReader.read(manifestURL: manifestURL, skillsBaseURL: skillsBase)

        #expect(contents.manifest.count == 2)
        #expect(contents.manifest[0] == SkillManifestEntry(name: "ralph", sha256: "aaa", priorSha256s: []))
        #expect(contents.manifest[1] == SkillManifestEntry(name: "grill-with-docs", sha256: "bbb", priorSha256s: ["old"]))

        #expect(contents.skills.count == 2)
        #expect(contents.skills[0].name == "ralph")
        #expect(contents.skills[0].fileURL == skillsBase.appendingPathComponent("ralph/SKILL.md"))
        #expect(contents.skills[1].name == "grill-with-docs")
        #expect(contents.skills[1].fileURL == skillsBase.appendingPathComponent("grill-with-docs/SKILL.md"))
    }

    @Test func bundleContentsCanMatchRequiredSkillsExactly() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = try writeManifest(
            PresenceChecker.requiredSkills.map { makeManifestEntry(name: $0) },
            to: root
        )
        let skillsBase = root.appendingPathComponent("Skills", isDirectory: true)

        let contents = try SkillBundleReader.read(manifestURL: manifestURL, skillsBaseURL: skillsBase)

        #expect(contents.manifest.map(\.name) == PresenceChecker.requiredSkills)
        #expect(contents.skills.map(\.name) == PresenceChecker.requiredSkills)
    }

    @Test func throwsManifestNotFoundWhenFileAbsent() {
        let bogus = URL(fileURLWithPath: "/tmp/no-such-manifest-\(UUID().uuidString).json")
        let skillsBase = URL(fileURLWithPath: "/tmp/skills")
        #expect {
            try SkillBundleReader.read(manifestURL: bogus, skillsBaseURL: skillsBase)
        } throws: { error in
            if case SkillBundleReader.ReadError.manifestNotFound = error { return true }
            return false
        }
    }

    @Test func throwsManifestMalformedWhenJsonIsGarbage() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = root.appendingPathComponent("skills-manifest.json")
        try "not valid json {{{".data(using: .utf8)!.write(to: manifestURL)

        #expect {
            try SkillBundleReader.read(manifestURL: manifestURL, skillsBaseURL: root)
        } throws: { error in
            if case SkillBundleReader.ReadError.manifestMalformed = error { return true }
            return false
        }
    }

    @Test func throwsManifestMalformedWhenJsonHasWrongShape() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = root.appendingPathComponent("skills-manifest.json")
        // Valid JSON but missing required fields.
        try #"[{"skill":"ralph"}]"#.data(using: .utf8)!.write(to: manifestURL)

        #expect {
            try SkillBundleReader.read(manifestURL: manifestURL, skillsBaseURL: root)
        } throws: { error in
            if case SkillBundleReader.ReadError.manifestMalformed = error { return true }
            return false
        }
    }

    @Test func emptyManifestReturnsEmptyCollections() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = try writeManifest([], to: root)
        let skillsBase = root.appendingPathComponent("Skills", isDirectory: true)

        let contents = try SkillBundleReader.read(manifestURL: manifestURL, skillsBaseURL: skillsBase)

        #expect(contents.skills.isEmpty)
        #expect(contents.manifest.isEmpty)
    }

    @Test func fileURLsPointInsideSkillsBaseDirectory() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = try writeManifest([makeManifestEntry(name: "qa")], to: root)
        let skillsBase = root.appendingPathComponent("Skills", isDirectory: true)

        let contents = try SkillBundleReader.read(manifestURL: manifestURL, skillsBaseURL: skillsBase)

        let skillURL = contents.skills[0].fileURL
        #expect(skillURL.path.hasPrefix(skillsBase.path))
        #expect(skillURL.lastPathComponent == "SKILL.md")
    }

    @Test func hasNoSideEffects() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = try writeManifest([makeManifestEntry(name: "ralph")], to: root)
        let skillsBase = root.appendingPathComponent("Skills", isDirectory: true)
        let manifestContent = try String(contentsOf: manifestURL, encoding: .utf8)

        _ = try SkillBundleReader.read(manifestURL: manifestURL, skillsBaseURL: skillsBase)

        // Manifest file must be unchanged and no extra files created.
        #expect(try String(contentsOf: manifestURL, encoding: .utf8) == manifestContent)
        let items = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(items == ["skills-manifest.json"])
    }
}
