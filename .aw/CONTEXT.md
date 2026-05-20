# Context

## Domain Language

| Term | Definition | Avoid |
| --- | --- | --- |
| **Call Sequence** | The ordered chain of function/method calls through a codebase, showing which calls which top-to-bottom. | Control flow, execution path |
| **Codebase** | The Swift source code under analysis. | Repository, project |
| **Flow View** | The visual tab/pane that renders a call sequence as a diagram. | Graph, flowchart |
| **Node** | One box in the call-sequence graph representing a function/method. Clicking a node highlights its definition in source. | Vertex, block, card |
| **Continuity Highlight** | When a node is selected, both the calling method and the called method's definitions are highlighted in the source panel to show the link. | |

## Relationships

- A **Codebase** is parsed to produce one or more **Call Sequences**.
- A **Flow View** renders a **Call Sequence**.

## Decisions

None yet.

## Decisions

- **Node-and-edge graph** for call sequence visualization, with source-code continuity highlighting.
- **tree-sitter** for parsing, chosen over swift-syntax for multi-language extensibility.

## Open Questions

- Should the app support multiple entry points, or does the user pick one?
- How are Swift call sites resolved (might reference protocols, extensions, dynamic dispatch)?
- Does the graph show the full call tree at once, or expand node-by-node on click?
