# ADR 0002: Excavation Runs Before grill-with-docs, Not Concurrent With It

## Status

Accepted

## Context

The Workbench needs an initial Outskirts inventory before the developer can make good architectural decisions. Two approaches were considered: (1) run excavation first, then begin grilling with the inventory already populated; (2) start grilling immediately and let excavation happen concurrently or on-demand.

The core risk with concurrent excavation is that the grill interview asks questions before the inventory is complete — the developer answers based on an incomplete picture, which is exactly the problem the Workbench is designed to prevent.

## Decision

The Plan phase sequence is:
1. Developer enters a **Braindump** (natural language feature description)
2. **Excavation Agent** runs autonomously, populating the initial Outskirts inventory
3. Once excavation completes, **grill-with-docs** begins with the Workbench already populated
4. During grilling, the developer or AI can add/remove Outskirts components iteratively
5. Developer constructs Inskirts architecture on the canvas
6. to-prd and scaffolding follow

The Braindump serves double duty: it seeds the Excavation Agent and provides the starting context for grill-with-docs.

## Consequences

- The developer sees a grounded inventory before answering any architectural questions — the primary goal of the Workbench.
- There is a waiting period between entering the Braindump and starting the grill interview. Excavation must be fast enough that this feels like loading, not blocking.
- grill-with-docs gains a new entry point (the Braindump) rather than starting cold.
