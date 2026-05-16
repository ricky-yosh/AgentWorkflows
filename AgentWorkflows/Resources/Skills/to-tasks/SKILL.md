---
name: to-tasks
description: Decompose a PRD.md into vertical-slice tasks.json backlog items tagged AFK or HITL for a Ralph loop.
---

# To Tasks

Convert `$1/PRD.md` into `$1/tasks.json` -- a machine-readable backlog that a Ralph loop can drive. Tasks must be vertical slices: each AFK task should deliver a thin but complete path through the relevant layers so the result is demoable after one Ralph iteration.

`$1` is the Progress Directory -- an absolute path passed as the first argument when the skill is invoked (for example, `/to-tasks /path/to/progress`). All input and output files live there. The Working Directory root is separate.

## Process

1. Read `$1/PRD.md`. If it doesn't exist, ask the user where the PRD lives.

2. If `.aw/CONTEXT.md` exists in the Working Directory root, read it and use its domain vocabulary when writing task descriptions and acceptance criteria.

3. Decompose the PRD's user stories, implementation decisions, testing decisions, and out-of-scope notes into tasks. Each task should:

   - Cut through all layers needed to produce observable behavior.
   - Take no more than roughly 30-90 minutes of focused work.
   - Have verifiable acceptance criteria that a developer or QA session could check without reading the implementation.
   - Be tagged `AFK` when Ralph can complete it autonomously.
   - Be tagged `HITL` when a human decision is required before implementation can safely proceed.
   - Declare real prerequisites in `blocked_by` as task ids, not prose notes.

4. Write `$1/tasks.json`. Overwrite any existing file without asking.

5. Print a one-line confirmation and the count: `Wrote N tasks to $1/tasks.json`. Do not list them -- the user can read the file.

## Task Schema

```json
[
  {
    "id": 1,
    "type": "AFK",
    "category": "engine",
    "description": "Add a visible task state transition from planning through verification",
    "acceptance_criteria": [
      "A session can advance through the full Plan, Build, and Verify path",
      "The Iterations tab shows the updated state after each transition",
      "The test suite compiles and passes"
    ],
    "effort": "medium",
    "blocked_by": [],
    "passes": false
  },
  {
    "id": 2,
    "type": "HITL",
    "category": "architecture",
    "description": "Decide whether iteration metadata is stored per session or per repository",
    "acceptance_criteria": [
      "The resolution names the chosen storage boundary",
      "The resolution explains the tradeoff that led to the decision"
    ],
    "effort": "low",
    "blocked_by": [],
    "resolution": "",
    "passes": false
  }
]
```

## Field Rules

- `id`: sequential integer starting at `1`. If a `tasks.json` already exists with tasks, continue the numbering.
- `type`: `"AFK"` or `"HITL"`. Use `"AFK"` only when the task can proceed without additional human judgment.
- `category`: short tag -- typical values: `schema`, `ui`, `engine`, `prompt`, `infrastructure`, `architecture`, `bug`, `docs`.
- `description`: one imperative sentence using domain language. No file paths. No line numbers.
- `acceptance_criteria`: independently verifiable outcomes, at most 5 items.
- `effort`: `"low"` | `"medium"` | `"high"` -- rough sizing.
- `blocked_by`: structured array of prerequisite task ids. Use `[]` when there are no prerequisites.
- `resolution`: required for `HITL` tasks and starts as an empty string. Omit it for `AFK` tasks.
- `passes`: always starts `false`. Ralph flips it to `true` when the task's acceptance criteria are met.

## Vertical Slice Rules

- Prefer tracer bullets over layer-first sequencing. A task that only changes schema, only changes engine plumbing, or only changes UI is acceptable only when it produces a directly verifiable behavior or unblocks multiple later vertical slices.
- Group tightly coupled schema, engine, and UI changes into one task when that is the smallest demoable unit.
- Keep tasks small enough for one Ralph iteration. If a vertical slice is too large, split it by user-visible scenario, not by code layer.
- Use `blocked_by` only for hard prerequisites. Do not encode loose sequencing preferences as dependencies.

## HITL Rules

- Create a `HITL` task when progress depends on product intent, irreversible architecture, security posture, data ownership, migration policy, or another decision that cannot be inferred safely from the PRD and `.aw/CONTEXT.md`.
- A `HITL` task should ask for a decision, not implementation work.
- Its acceptance criteria should define what a complete resolution must answer.
- Keep `resolution` empty. The user fills it in later; Ralph records it when processing the resolved task.

## Ordering

List tasks in the order Ralph should consider them:

1. Early HITL decisions that block implementation.
2. Thin AFK tracer bullets that prove the main workflow end to end.
3. Additional AFK slices by user-visible scenario.
4. Follow-up infrastructure, docs, or cleanup tasks only when they are required by the PRD.

## Rules

- **No more than about 15 tasks** in one pass. If the PRD is larger than that, tell the user the PRD should be split.
- **No file paths or line numbers** in descriptions or acceptance criteria. They go stale.
- **No standalone test tasks** unless testing is the feature. Assume Ralph writes tests alongside each implementation task.
- **No freeform dependency notes.** Use `blocked_by` for dependencies and keep it as an array of ids.
- **Do not mark any generated task as passed.** Every task starts with `passes: false`.
