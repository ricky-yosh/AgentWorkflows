# ADR 0006: Two-Phase Excavation — ast-grep Extracts, AI Selects

## Status

Accepted

## Context

The Excavation Agent needs to surface relevant existing codebase components (Outskirts nodes) from a potentially large or mixed-language repo. The original PRD described the agent as scanning autonomously using Bash, grep, and file tools — a pure AI crawl. This approach burns context fast, misses things on large repos, and has AI doing work an algorithm can do deterministically.

Tools like Sourcegraph and CodeSee solve this by parsing first and reasoning second: a language-aware parser extracts a symbol index deterministically, then reasoning happens over the index rather than raw files.

## Decision

Excavation runs in two phases:

**Phase 1 — Deterministic extraction (ast-grep):**
The app runs ast-grep (bundled binary in app Resources) against the repo, using language-specific patterns to extract all named types and their public members. Output is a compact symbol index: name, file path, public properties/methods per type. ast-grep respects `.gitignore` by default; a hardcoded ignore list covers common build artifact directories (`Pods`, `.build`, `DerivedData`, `target`, `node_modules`, `dist`).

**Phase 2 — AI selection:**
ExcavationAgent receives the symbol index and the braindump. AI selects the 10–15 nodes architecturally relevant to the feature and writes them to `canvas.toml`. The full symbol index never reaches grill-with-docs — only `canvas.toml` with the selected nodes.

**App owns all ast-grep invocations.** The binary is bundled with the app. When grill-with-docs discovers a new component mid-interview, it writes name + file path only to `canvas.toml`. The app watches `canvas.toml`, detects the new entry, runs ast-grep on that specific file, and enriches the entry with pins. AI never invokes ast-grep directly.

**Supported languages (MVP):** Swift, Objective-C, JavaScript, Python, GDScript. For unsupported languages, ExcavationAgent surfaces an explicit warning and the canvas starts empty — developer excavates via chat only.

**Directory scoping deferred.** The two-phase model combined with `.gitignore` exclusions keeps the index tractable for known mixed repos (Swift+Obj-C, Angular+Go). Scoping is a purely additive optimization if index size proves problematic in practice.

## Consequences

- ast-grep binary must be bundled in app Resources and kept updated (low maintenance — core API is stable).
- ExcavationAgent splits into two distinct steps: extraction (ast-grep subprocess) and selection (AI call with symbol index).
- Language-specific ast-grep patterns must be maintained for each supported language. Unsupported languages degrade gracefully with an explicit warning.
- The app-enriches-pins flow (app watches canvas.toml, runs ast-grep on new entries) requires CanvasFileStore to detect incomplete entries and trigger enrichment.
- Pin-to-pin connection precision deferred post-MVP; node-to-node connections use the pin list for reference only.
