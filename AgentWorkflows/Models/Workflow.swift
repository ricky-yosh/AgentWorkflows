import Foundation

struct Workflow: Codable, Equatable {
    var name: String
    /// Agent profile applied to every step in every phase unless overridden
    /// at the phase or step level. `nil` falls back to the user's app-level
    /// default agent preference. Encoded as `default_agent` in YAML.
    var defaultAgent: String?
    var phases: [Phase]

    enum CodingKeys: String, CodingKey {
        case name, phases
        case defaultAgent = "default_agent"
    }

    init(name: String, defaultAgent: String? = nil, phases: [Phase]) {
        self.name = name
        self.defaultAgent = defaultAgent
        self.phases = phases
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        defaultAgent = try c.decodeIfPresent(String.self, forKey: .defaultAgent)
        phases = try c.decode([Phase].self, forKey: .phases)
    }
}

struct Phase: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    /// Agent profile applied to every step in this phase unless the step
    /// sets its own `agent`. Encoded as `default_agent` in YAML.
    var defaultAgent: String?
    var steps: [WorkflowStep]

    enum CodingKeys: String, CodingKey {
        case name, steps
        case defaultAgent = "default_agent"
    }

    init(name: String, defaultAgent: String? = nil, steps: [WorkflowStep]) {
        self.name = name
        self.defaultAgent = defaultAgent
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        defaultAgent = try c.decodeIfPresent(String.self, forKey: .defaultAgent)
        steps = try c.decode([WorkflowStep].self, forKey: .steps)
    }

    static func == (lhs: Phase, rhs: Phase) -> Bool {
        lhs.name == rhs.name && lhs.defaultAgent == rhs.defaultAgent && lhs.steps == rhs.steps
    }
}

struct WorkflowStep: Codable, Equatable, Identifiable {
    var id: String
    var type: StepType
    var label: String?
    var agent: String?
    var prompt: String?
    var promptFile: String?
    var steps: [WorkflowStep]?
    /// Safety cap on Iteration count for `loop` and `iterate_tasks` steps.
    /// Optional; omitting it preserves the unbounded behavior. Encoded as
    /// `max_iterations` in YAML.
    var maxIterations: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, label, agent, prompt, steps
        case promptFile = "prompt_file"
        case maxIterations = "max_iterations"
    }

    init(id: String, type: StepType, label: String? = nil, agent: String?, prompt: String?, promptFile: String?, steps: [WorkflowStep]? = nil, maxIterations: Int? = nil) {
        self.id = id
        self.type = type
        self.label = label
        self.agent = agent
        self.prompt = prompt
        self.promptFile = promptFile
        self.steps = steps
        self.maxIterations = maxIterations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        type = try container.decode(StepType.self, forKey: .type)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        promptFile = try container.decodeIfPresent(String.self, forKey: .promptFile)
        steps = try container.decodeIfPresent([WorkflowStep].self, forKey: .steps)
        maxIterations = try container.decodeIfPresent(Int.self, forKey: .maxIterations)
    }
}

enum StepType: String, Codable, Equatable {
    case prompt
    case restartCLI
    case pause
    case break_ = "break"
    case comment
    case loop
    case iterateTasks = "iterate_tasks"
}

struct WorkflowValidationError: Error {
    let message: String
}

extension Workflow {
    /// Resolves the agent reference for a step, walking the inheritance
    /// chain: step.agent → phase.defaultAgent → workflow.defaultAgent →
    /// nil (caller falls back to app-level default).
    ///
    /// `step` must belong to `phase` for the result to be meaningful.
    func resolvedAgent(for step: WorkflowStep, in phase: Phase) -> String? {
        if let a = step.agent, !a.isEmpty { return a }
        if let a = phase.defaultAgent, !a.isEmpty { return a }
        if let a = defaultAgent, !a.isEmpty { return a }
        return nil
    }

    /// The one Workflow the app ships. Inlined in Swift so the Workflow
    /// definition is versioned with the code that executes it; there is no
    /// YAML loader, no WorkflowStore, no user-editable surface. Each
    /// prompt Step invokes a Skill by slash command — Skills are the
    /// single source of truth for what the Agent does in that Phase.
    static let ralph = Workflow(
        name: "Ralph",
        defaultAgent: "cli/claude",
        phases: [
            Phase(name: "Plan", steps: [
                WorkflowStep(id: "plan-grill-me", type: .prompt, label: "Grill Me",
                             agent: nil, prompt: "/grill-me", promptFile: nil),
                WorkflowStep(id: "plan-ubiquitous-language", type: .prompt, label: "Update Ubiquitous Language",
                             agent: nil, prompt: "/ubiquitous-language", promptFile: nil),
                WorkflowStep(id: "plan-to-prd", type: .prompt, label: "Write PRD",
                             agent: nil, prompt: "/to-prd {progress-path}", promptFile: nil),
                WorkflowStep(id: "plan-prd-to-tasks", type: .prompt, label: "PRD to Tasks",
                             agent: nil, prompt: "/prd-to-tasks {progress-path}", promptFile: nil),
            ]),
            Phase(name: "Build", steps: [
                WorkflowStep(id: "build-iterate", type: .iterateTasks, label: nil,
                             agent: nil, prompt: nil, promptFile: nil,
                             steps: [
                                WorkflowStep(id: "build-ralph", type: .prompt, label: "Ralph",
                                             agent: nil, prompt: "/ralph {progress-path}", promptFile: nil),
                             ],
                             maxIterations: 25),
            ]),
            Phase(name: "Verify", steps: [
                WorkflowStep(id: "verify-restart-cli", type: .restartCLI, label: nil,
                             agent: nil, prompt: nil, promptFile: nil),
                WorkflowStep(id: "verify-qa", type: .prompt, label: "QA Session",
                             agent: nil, prompt: "/qa {progress-path}", promptFile: nil),
            ]),
        ]
    )

    /// Validates workflow constraints. Throws if any loop or iterate_tasks step
    /// has an empty or nil steps array.
    func validate() throws {
        for phase in phases {
            for step in phase.steps {
                if step.type == .loop || step.type == .iterateTasks {
                    guard let children = step.steps, !children.isEmpty else {
                        throw WorkflowValidationError(
                            message: "Step of type '\(step.type.rawValue)' in phase '\(phase.name)' must have a non-empty steps array"
                        )
                    }
                } else if step.maxIterations != nil {
                    throw WorkflowValidationError(
                        message: "Step of type '\(step.type.rawValue)' in phase '\(phase.name)' must not declare max_iterations — it only applies to loop or iterate_tasks steps"
                    )
                }
            }
        }
    }
}
