---
name: grill-with-docs
description: Interview the user about a plan while updating .aw/CONTEXT.md inline and recording architectural decisions in .aw/adr/.
---

# Grill With Docs

Interview the user relentlessly about a plan or design until we reach shared understanding. Capture the domain language and durable decisions as they are resolved, not as a cleanup pass at the end.

## Canonical Files

- Vocabulary lives at `.aw/CONTEXT.md` in the Working Directory root.
- Architectural Decision Records live in `.aw/adr/`.
- Read existing `.aw/CONTEXT.md` before asking questions if it exists.
- Read existing `.aw/adr/` entries before asking questions if the directory exists.

## Process

1. Restate the plan in one short paragraph and name the biggest uncertainties.
2. If `.aw/CONTEXT.md` exists, compare the user's current wording against it. Challenge inconsistent, overloaded, or vague terms immediately.
3. Ask one question at a time. Walk the decision tree deliberately, resolving dependencies before downstream choices.
4. For each question, provide your recommended answer and the tradeoff behind it.
5. If a question can be answered by exploring the codebase, explore the codebase instead of asking the user.
6. When a term is resolved, update `.aw/CONTEXT.md` immediately before asking the next question.
7. When a hard-to-reverse architectural decision is resolved, decide whether it needs an ADR using the ADR criteria below. If it qualifies, write the ADR before asking the next question.
8. Continue until the plan, vocabulary, and durable decisions are coherent enough for `/to-prd` to produce a PRD without re-interviewing the user.

## CONTEXT.md Format

Keep `.aw/CONTEXT.md` concise and useful to future implementation agents:

```md
# Context

## Domain Language

| Term | Definition | Avoid |
| --- | --- | --- |
| **Workflow** | A configured sequence of steps that moves a session through planning, building, and verification. | Pipeline |

## Relationships

- A **Session** runs one **Workflow** against one repository.

## Decisions

- Use **Progress Directory** for per-session generated artifacts.

## Open Questions

- Decide whether external issue trackers are in scope.
```

Rules for `.aw/CONTEXT.md`:

- Use domain terms, not implementation trivia.
- Prefer one-sentence definitions.
- Record aliases to avoid when they prevent future ambiguity.
- Remove an open question once it is resolved.
- Keep existing valid terms unless the user explicitly changes the meaning.
- If the user changes a term, update the definition and note the replaced wording in `Avoid`.

## ADR Criteria

Write an ADR only when all three criteria are true:

1. The decision is hard to reverse.
2. The decision would be surprising without context.
3. The decision is the result of a real tradeoff.

Do not write ADRs for routine implementation details, obvious defaults, or decisions that can be changed cheaply.

## ADR Format

Create `.aw/adr/` if needed. Name ADR files with a zero-padded sequence and a short slug, for example `.aw/adr/0001-use-context-md.md`.

```md
# ADR 0001: Use CONTEXT.md for Workflow Vocabulary

## Status

Accepted

## Context

The relevant forces, constraints, and tradeoffs.

## Decision

The decision in one or two paragraphs.

## Consequences

- Positive consequence.
- Negative or limiting consequence.
```

## Question Style

- Ask exactly one question at a time.
- Keep questions concrete and answerable.
- Include your recommended answer with the question.
- Surface assumptions instead of hiding them.
- Push back when a request conflicts with `.aw/CONTEXT.md`, an ADR, or the user's stated goals.
- Stop and ask when a decision depends on missing human intent.
