# ADR 0004: Canvas and PRD Are Orthogonal Artifacts

## Status

Accepted

## Context

After grilling and canvas construction, the Workflow needs durable artifacts that implementation agents (ralph) can reference. Two candidates exist: the PRD (requirements) and the Canvas (architecture). The question was whether to merge them, feed one into the other, or keep them separate.

## Decision

The Canvas and PRD are orthogonal and coexist as separate artifacts:

- **PRD** — user stories, implementation contracts (module responsibilities, interfaces, data flow), and testing decisions. Written in prose; describes what each module does and why.
- **Canvas artifact (ARCHITECTURE.toml)** — structural graph; captures Inskirts nodes (new components with pattern type and role), connected Outskirts nodes (existing anchors), and typed connections between them. Describes how modules wire together, not what they do internally.

The two artifacts describe the same feature at different levels of abstraction. The PRD is the prose contract; ARCHITECTURE.toml is the wiring diagram. Ralph reads both: prose to understand module responsibilities, graph to understand structural relationships. Neither feeds into the other.

## Consequences

- The Plan phase now produces one more artifact. The canonical reference set for a feature is: CONTEXT.md, PRD.md, ADRs, tasks.json, and ARCHITECTURE.toml.
- The Canvas serialization must be concise and LLM-efficient — it will be included in implementation agent context repeatedly.
- Modules in the PRD's Implementation Decisions section naturally map to Inskirts nodes on the canvas — the same components described from two angles. This is intentional, not redundant.
