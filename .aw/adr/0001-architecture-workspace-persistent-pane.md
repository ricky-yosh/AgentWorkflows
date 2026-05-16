# ADR 0001: Architecture Workspace is a Persistent Pane, Not a Discrete Skill

## Status

Accepted

## Context

The Architecture Workspace needs to support iterative excavation across the entire Plan phase — during grilling, PRD writing, and scaffolding. A discrete skill (like `/grill-with-docs`) has a clear start and end, which would force the developer to re-enter excavation context every time they want to ask a new question. The inventory of discovered components needs to persist across all Plan-phase activities.

## Decision

The Architecture Workspace is implemented as a persistent UI pane that remains active throughout the Plan phase. It accumulates Inventory Items from multiple sources: the initial scan, explorations during grilling, direct developer questions, and anything surfaced during PRD or task generation. When Claude discovers a component, pattern, or relationship worth surfacing, it auto-adds it to the Inventory — the same way ADRs are auto-written when a qualifying decision is reached — without waiting for an explicit developer action.

## Consequences

- The inventory is the shared context between the developer and AI across all Plan-phase activities. Context is never lost between steps.
- Auto-add risks inventory clutter if Claude surfaces too aggressively. The AI must apply the same judgment as ADR creation: only add items that are non-obvious and useful to the feature being planned.
- The pane requires a persistent data model (the Inventory) that survives navigation between Plan-phase steps, rather than living only in a conversation thread.
