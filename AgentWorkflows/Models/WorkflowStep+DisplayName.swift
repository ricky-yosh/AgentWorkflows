import Foundation

extension WorkflowStep {
    var displayName: String {
        if let label, !label.isEmpty { return label }
        return computedDisplayName
    }

    var computedDisplayName: String {
        if let file = promptFile, !file.isEmpty {
            var name = file
            if name.hasSuffix(".md") { name = String(name.dropLast(3)) }
            return name.split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        switch type {
        case .prompt:       return "Prompt"
        case .restartCLI:   return "Restart CLI"
        case .pause:        return "Pause"
        case .break_:       return "Break"
        case .comment:      return "Comment"
        case .loop:         return "Loop"
        case .iterateTasks: return "Iterate Tasks"
        }
    }
}
