# ADR 0009: EngineManager Uses a Composite (SessionID, EngineRole) Key

## Status

Accepted

## Context

ExcavationChatView requires a second `AgentEngine` instance per session — running a different CLI (ExcavationCLIPreference) and staying alive independently of the main grill/ralph engine. `EngineManager` currently keys engines by `session.id` alone, which doesn't support two engines per session.

Two approaches were considered:
- **Separate dictionary** — `excavationEngine(for:)` backed by its own `[UUID: AgentEngine]`. Parallel but independent from `engine(for:tool:)`.
- **Composite key** — introduce `EngineRole: Hashable { case main, excavation }` and key the single engine dictionary by `(UUID, EngineRole)`.

## Decision

EngineManager adopts a composite key `(sessionID: UUID, role: EngineRole)`. `EngineRole` is an enum with at minimum `.main` and `.excavation` cases. All existing call sites map to `.main`; the excavation engine uses `.excavation`.

Preferred over a separate dictionary because: (1) one dictionary keeps cleanup (session teardown, memory pressure) consistent; (2) the role is explicit at every call site rather than implied by which method you call; (3) extensible if a third role (e.g. a dedicated QA agent) is ever added.

## Consequences

- All existing `engineManager.engine(for: session.id, ...)` call sites must be updated to pass `role: .main` (mechanical, additive change).
- WorkflowInspector can surface which role a step targets — useful for showing whether a step runs in the main or excavation terminal.
- If a third `EngineRole` is added later, the key schema already supports it without dictionary proliferation.
