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

    static func execute(plan: SkillInstaller.Plan, skillsDirectory: URL, target: SkillTarget) -> [OpResult] {
        var results: [OpResult] = []
        let fm = FileManager.default

        for op in plan.ops {
            switch op {
            case .install(let name, let sourceURL):
                let destFile = SkillClassifier.installedSkillFileURL(
                    skillsDirectory: skillsDirectory,
                    skillName: name,
                    target: target
                )
                let destDir = target == .openCode ? skillsDirectory : destFile.deletingLastPathComponent()
                do {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    let data = try Data(contentsOf: sourceURL)
                    try data.write(to: destFile, options: .atomic)
                    results.append(OpResult(skillName: name, outcome: .succeeded))
                } catch {
                    results.append(OpResult(skillName: name, outcome: .failed(error.localizedDescription)))
                }

            case .update(let name, let sourceURL, _):
                let destFile = SkillClassifier.installedSkillFileURL(
                    skillsDirectory: skillsDirectory,
                    skillName: name,
                    target: target
                )
                let destDir = target == .openCode ? skillsDirectory : destFile.deletingLastPathComponent()
                do {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    let data = try Data(contentsOf: sourceURL)
                    try data.write(to: destFile, options: .atomic)
                    results.append(OpResult(skillName: name, outcome: .succeeded))
                } catch {
                    results.append(OpResult(skillName: name, outcome: .failed(error.localizedDescription)))
                }

            case .remove(let name):
                let destFile = SkillClassifier.installedSkillFileURL(
                    skillsDirectory: skillsDirectory,
                    skillName: name,
                    target: target
                )
                let removeURL = target == .openCode ? destFile : destFile.deletingLastPathComponent()
                do {
                    try fm.removeItem(at: removeURL)
                    results.append(OpResult(skillName: name, outcome: .succeeded))
                } catch {
                    results.append(OpResult(skillName: name, outcome: .failed(error.localizedDescription)))
                }
            }
        }

        return results
    }
}
