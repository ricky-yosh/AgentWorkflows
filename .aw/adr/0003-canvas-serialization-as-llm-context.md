# ADR 0003: Canvas State Is Serialized to LLM-Readable Text and Passed to the Grill AI

## Status

Accepted

## Context

The developer builds Inskirts components during grill-with-docs, not after. For this to be useful, the grill AI must be able to see what the developer is constructing — not just the conversation transcript. The canvas is a visual UI with positional data, node objects, and edge structures that the AI cannot reason about directly.

Two approaches: (1) pass raw canvas state (JSON node graph with coordinates); (2) serialize the canvas to a semantic text description and pass that.

## Decision

The Workbench maintains a **Canvas Serialization** — a running LLM-readable text description of the current canvas state — persisted as a file in the session directory (e.g., `canvas.toml`). This serialization includes: node names, types (pattern or generic block), inferred roles, and connections (from → to, with relationship type). It omits all positional/layout data.

The data flow is file-mediated across the process boundary:
- The SwiftUI app writes canvas state to `canvas.toml` when the developer places or connects nodes.
- The Excavation Agent and grill-with-docs skill read `canvas.toml` for context and write new Outskirts discoveries back to it.
- The app watches `canvas.toml` via `DirectoryWatcher` and updates the canvas in real time when the file changes.
- The grill-with-docs skill is updated to read `canvas.toml` at the start of each question loop and append new Outskirts items when it discovers relevant components.

## Consequences

- The canvas data model must support semantic serialization alongside visual layout.
- `DirectoryWatcher` wires the file changes back into the SwiftUI view layer — no new file-watching infrastructure needed.
- The grill-with-docs skill requires an update to read/write `canvas.toml` — this is a second deliverable within the same MVP.
- Serialization must be kept concise; a verbose canvas dump will consume CLI context and dilute the grill conversation.
