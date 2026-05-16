import Foundation

enum SkillInstaller {

    struct SkillInput: Equatable {
        let name: String
        let classification: SkillClassifier.State
        let sourceURL: URL
    }

    enum UserIntent {
        case firstRun
        case updateAllClean
        case updateAll
        case removeAllUnmodified
        case updateSpecific(name: String)
        case removeSpecific(name: String)
    }

    enum Op: Equatable {
        case install(name: String, sourceURL: URL)
        case update(name: String, sourceURL: URL, requiresConsent: Bool)
        case remove(name: String)
    }

    struct BlockedOp: Equatable {
        let skillName: String
        let reason: String
    }

    struct Plan: Equatable {
        let ops: [Op]
        let blocked: [BlockedOp]
    }

    static func plan(skills: [SkillInput], intent: UserIntent) -> Plan {
        var ops: [Op] = []
        var blocked: [BlockedOp] = []

        switch intent {
        case .firstRun:
            for skill in skills where skill.classification == .missing {
                ops.append(.install(name: skill.name, sourceURL: skill.sourceURL))
            }

        case .updateAllClean:
            for skill in skills {
                switch skill.classification {
                case .clean, .stale:
                    ops.append(.update(name: skill.name, sourceURL: skill.sourceURL, requiresConsent: false))
                case .modified, .missing:
                    break
                }
            }

        case .updateAll:
            for skill in skills {
                switch skill.classification {
                case .clean, .stale:
                    ops.append(.update(name: skill.name, sourceURL: skill.sourceURL, requiresConsent: false))
                case .modified:
                    ops.append(.update(name: skill.name, sourceURL: skill.sourceURL, requiresConsent: true))
                case .missing:
                    break
                }
            }

        case .removeAllUnmodified:
            for skill in skills {
                switch skill.classification {
                case .clean, .stale:
                    ops.append(.remove(name: skill.name))
                case .modified:
                    blocked.append(BlockedOp(skillName: skill.name, reason: "Skill has been locally modified and cannot be removed without explicit confirmation."))
                case .missing:
                    break
                }
            }

        case .updateSpecific(let name):
            guard let skill = skills.first(where: { $0.name == name }) else { break }
            switch skill.classification {
            case .clean, .stale:
                ops.append(.update(name: skill.name, sourceURL: skill.sourceURL, requiresConsent: false))
            case .modified:
                ops.append(.update(name: skill.name, sourceURL: skill.sourceURL, requiresConsent: true))
            case .missing:
                ops.append(.install(name: skill.name, sourceURL: skill.sourceURL))
            }

        case .removeSpecific(let name):
            guard let skill = skills.first(where: { $0.name == name }) else { break }
            switch skill.classification {
            case .clean, .stale:
                ops.append(.remove(name: skill.name))
            case .modified:
                blocked.append(BlockedOp(skillName: skill.name, reason: "Skill has been locally modified and cannot be removed without explicit confirmation."))
            case .missing:
                break
            }
        }

        return Plan(ops: ops, blocked: blocked)
    }
}
