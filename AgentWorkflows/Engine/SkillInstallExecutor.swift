import Foundation

enum SkillInstallExecutor {

    enum Outcome: Equatable {
        case succeeded
        case failed(String)
    }

    struct OpResult: Equatable {
        let skillName: String
        let outcome: Outcome
    }

    static func execute(plan: SkillInstaller.Plan, skillsDirectory: URL) -> [OpResult] {
        var results: [OpResult] = []
        let fm = FileManager.default

        for op in plan.ops {
            switch op {
            case .install(let name, let sourceURL):
                let destDir = skillsDirectory.appendingPathComponent(name)
                let destFile = destDir.appendingPathComponent("SKILL.md")
                do {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    let data = try Data(contentsOf: sourceURL)
                    try data.write(to: destFile, options: .atomic)
                    results.append(OpResult(skillName: name, outcome: .succeeded))
                } catch {
                    results.append(OpResult(skillName: name, outcome: .failed(error.localizedDescription)))
                }

            case .update(let name, let sourceURL, _):
                let destDir = skillsDirectory.appendingPathComponent(name)
                let destFile = destDir.appendingPathComponent("SKILL.md")
                do {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    let data = try Data(contentsOf: sourceURL)
                    try data.write(to: destFile, options: .atomic)
                    results.append(OpResult(skillName: name, outcome: .succeeded))
                } catch {
                    results.append(OpResult(skillName: name, outcome: .failed(error.localizedDescription)))
                }

            case .remove(let name):
                let destDir = skillsDirectory.appendingPathComponent(name)
                do {
                    try fm.removeItem(at: destDir)
                    results.append(OpResult(skillName: name, outcome: .succeeded))
                } catch {
                    results.append(OpResult(skillName: name, outcome: .failed(error.localizedDescription)))
                }
            }
        }

        return results
    }
}
