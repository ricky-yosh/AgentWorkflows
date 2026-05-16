# ADR 0007: ExcavationAgent Is a Skill; App Pre-Runs ast-grep

## Status

Accepted

## Context

ADR 0006 established two-phase excavation: ast-grep extracts a symbol index deterministically (Phase 1), then AI selects relevant nodes (Phase 2). The original model treated ExcavationAgent as a single Swift module that owned both phases — it would invoke the bundled ast-grep binary directly and then call an AI API.

The question was whether ExcavationAgent should be a Swift module or a skill (a CLI process running in a terminal, like grill-with-docs). Making it a skill has a key advantage: it can run against a different, cheaper model via the Excavation CLI preference — excavation is a bounded one-shot task that doesn't need the same model as the main workflow. But skills are CLI processes and cannot invoke the app-bundled ast-grep binary.

## Decision

ExcavationAgent is a skill, not a Swift module. It runs in the ExcavationChatView terminal automatically at session start.

To preserve ADR 0006's constraint that "the app owns all ast-grep invocations," the app performs Phase 1 before launching the skill: it runs the bundled ast-grep binary as a subprocess, writes `symbol-index.md` to the session directory, then launches the ExcavationAgent skill. The skill reads `symbol-index.md` and `braindump.md`, performs Phase 2 AI selection, and writes the initial Outskirts to `canvas.toml`. The skill never invokes ast-grep directly.

After the skill completes, the developer continues in the same ExcavationChatView terminal for freeform follow-up excavation questions. This terminal is distinct from the main terminal where grill-with-docs runs.

## Consequences

- The app must run ast-grep as a subprocess before invoking the ExcavationAgent skill — WorkflowEngine owns this sequencing.
- `symbol-index.md` is a transient session-scoped artifact in the session directory (not `.aw/`); it is meaningless after excavation completes.
- ExcavationCLIPreference is a dedicated section in the preferences pane for configuring which CLI target runs ExcavationAgent, independent from the main workflow CLI target.
- ADR 0006's constraint ("app owns all ast-grep invocations") is preserved — the skill reads a pre-built index, never touches ast-grep directly.
- The boundary between app-side extraction and skill-side selection is file-mediated, consistent with the cross-boundary communication decision (ADR 0003).
