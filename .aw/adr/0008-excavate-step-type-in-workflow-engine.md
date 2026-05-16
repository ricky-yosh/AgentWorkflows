# ADR 0008: `excavate` Is a New WorkflowEngine Step Type

## Status

Accepted

## Context

The Plan phase sequence (ADR 0002) requires: (1) running ast-grep as an app-side subprocess to produce `symbol-index.md`, then (2) dispatching the ExcavationAgent skill to a second terminal (ExcavationChatView). This two-part operation doesn't fit any existing WorkflowEngine step type (`prompt`, `restartCLI`, `pause`, `break_`, `comment`, `iterateTasks`, `loop`).

Two alternatives were considered:
- **Hook in `SessionSeedSheet.onConfirm`** — fire ast-grep + ExcavationAgent before `startRalphLoop()`. No engine changes needed, but the step is invisible to WorkflowInspector and can't be replayed via "Run from here."
- **New `excavate` step type** — WorkflowEngine handles the step, making it inspectable and replayable.

## Decision

A new `excavate` step type is added to the Workflow JSON and WorkflowEngine. When executed, the step: (1) runs the bundled ast-grep binary as a subprocess to produce `symbol-index.md` in the session directory, then (2) dispatches the ExcavationAgent skill prompt to the excavation engine (a second `AgentEngine` instance keyed separately from the main session engine). The step completes when the ExcavationAgent skill exits (same signal mechanism as `prompt` steps).

This keeps all Plan-phase sequencing inside the Workflow model — visible in WorkflowInspector, replayable via "Run from here," and consistent with how `grill-with-docs` is driven as a `prompt` step.

## Consequences

- WorkflowEngine gains one new step type (`excavate`); the Workflow JSON schema is extended.
- EngineManager must track two `AgentEngine` instances per session: the main engine (grill/ralph) and the excavation engine.
- The step is inspectable and replayable, which is the primary reason to choose this over a `SessionSeedSheet` hook.
- If ast-grep fails (binary missing, unsupported language), the step must surface a clear error and allow the user to continue — the excavation phase degrades gracefully to chat-only, per ADR 0006.
