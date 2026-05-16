# ADR 0010: Repository-Wide Symbol Index Shared Across Planning Agents

## Status

Accepted

## Context

The current excavation design treats `symbol-index.toml` as a session artifact built for one feature and consumed mainly by ExcavationAgent. That keeps the first implementation simple, but it repeats indexing work for every new session and forces other planning agents to fall back to ad hoc repo exploration.

The product goal is closer to Sourcegraph's operating model at a smaller scale: deterministic code indexing first, agent reasoning second. To get the efficiency benefit, the index has to outlive any single feature session and be available to every planning agent that needs bounded codebase context.

## Decision

`symbol-index.toml` is a repository-wide artifact, not a session artifact. The app builds and refreshes it at the repository scope, and new sessions reuse the existing index instead of reindexing from scratch.

ExcavationAgent, grill-with-docs, and any future planning-phase agents start from this shared Symbol Index for initial codebase context. They may open specific files after consulting the index, but they should not begin with repo-wide search. Session artifacts remain session-scoped: `canvas.toml`, `canvas-layout.toml`, `ARCHITECTURE.toml`, and other per-feature outputs do not become shared.

## Consequences

- New sessions start faster because they reuse an existing repository index.
- Planning agents share one consistent view of the codebase symbol surface.
- The app now needs an invalidation and refresh strategy for repository indexing.
- The storage location and lifecycle of `symbol-index.toml` must be separated clearly from per-session artifacts.
