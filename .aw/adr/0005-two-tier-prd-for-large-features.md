# ADR 0005: Two-Tier PRD Structure for Large Features

## Status

Rejected — deferred post-MVP. One PRD exists per session; multi-tier decomposition adds maintenance overhead that isn't justified before the Workbench has been used in practice.

## Context

When a feature is too large to implement in a single session, the standard grill-with-docs → to-prd → to-tasks workflow breaks down: a single PRD would produce too many tasks, the canvas would be too dense to reason about, and ralph would lack a bounded scope. The question was how to decompose the feature without losing the enriched understanding built up during excavation and grilling.

Three approaches were considered:
1. Split at the braindump level — start two blank sessions with scoped braindumps
2. Let the canvas topology drive decomposition — developer reads the dense canvas and manually scopes child sessions
3. Produce a parent PRD with module stubs — grill-with-docs focuses on decomposition first, child PRDs follow per slice

The risk with (1) is that the enriched understanding built during excavation (discovered dependencies, architectural constraints, partial canvas) is lost — the braindump captures initial inspiration, not the fleshed-out state at the moment of splitting. The risk with (2) is that there's no durable artifact capturing the decomposition rationale or slice boundaries.

## Decision

Large features use a two-tier PRD structure:

- **Parent PRD** — produced by grill-with-docs in parent PRD mode. Contains the full problem statement, full scope, module stubs (name + one-line responsibility), and slice assignments. The developer iterates on it until slice boundaries feel right. Slices are assigned at the module level (conceptual units of responsibility), not at the Swift type level.
- **Child PRD** — a full implementable PRD scoped to one slice of the parent PRD, produced in a separate grill-with-docs session with the parent PRD as context. Contains user stories, implementation decisions, and testing decisions for the assigned modules only.

Parent PRD mode is **developer-declared upfront**. The developer signals before grilling begins that the feature is large. The grill AI may suggest it if the canvas gets very dense, but does not switch modes automatically — the developer confirms.

Slices follow **tracer bullet** philosophy: each child session gets a thin vertical strip that runs end-to-end through a few modules, not a horizontal layer (all data models, then all views). The developer has full influence over slice boundaries via the parent PRD's decomposition section.

## Consequences

- The Workflow gains a conditional branch: single-session features follow the existing path; large features go through parent PRD → N child PRD sessions.
- The grill-with-docs skill needs to support parent PRD mode as a distinct output target.
- The to-prd skill needs a corresponding "child PRD" mode that reads the parent PRD as context and scopes its output to the assigned modules.
- The enriched canvas state at split time is preserved — the parent PRD session's canvas.toml and grill transcript remain in the session directory as durable context.
