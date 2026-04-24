import Foundation

/// Pure-function reader that enumerates the Skill Bundle and loads the Skill Manifest.
/// All I/O is read-only and scoped to the provided URLs (or `Bundle.main` by default).
enum SkillBundleReader {

    struct BundledSkill: Equatable {
        let name: String
        let fileURL: URL
    }

    struct BundleContents: Equatable {
        let skills: [BundledSkill]
        let manifest: [SkillManifestEntry]
    }

    enum ReadError: Error {
        case manifestNotFound
        case manifestMalformed(underlying: Error)
    }

    /// Reads the Skill Bundle from `Bundle.main`.
    static func read(from bundle: Bundle = .main) throws -> BundleContents {
        guard let manifestURL = bundle.url(forResource: "skills-manifest", withExtension: "json") else {
            throw ReadError.manifestNotFound
        }
        let skillsBaseURL = manifestURL
            .deletingLastPathComponent()
            .appendingPathComponent("Skills", isDirectory: true)
        return try read(manifestURL: manifestURL, skillsBaseURL: skillsBaseURL)
    }

    /// Reads the Skill Bundle from explicit URLs — the primary entry point for tests.
    static func read(manifestURL: URL, skillsBaseURL: URL) throws -> BundleContents {
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw ReadError.manifestNotFound
        }

        let manifest: [SkillManifestEntry]
        do {
            manifest = try JSONDecoder().decode([SkillManifestEntry].self, from: data)
        } catch {
            throw ReadError.manifestMalformed(underlying: error)
        }

        let skills = manifest.map { entry in
            BundledSkill(
                name: entry.name,
                fileURL: skillsBaseURL
                    .appendingPathComponent(entry.name, isDirectory: true)
                    .appendingPathComponent("SKILL.md")
            )
        }

        return BundleContents(skills: skills, manifest: manifest)
    }
}
