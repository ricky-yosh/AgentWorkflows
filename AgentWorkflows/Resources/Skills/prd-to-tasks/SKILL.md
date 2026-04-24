---
name: prd-to-tasks
description: Decompose a PRD.md into a structured tasks.json backlog for a Ralph loop. Each task is small enough to complete in a single iteration. Use when user has a PRD and needs a machine-readable task list, or mentions "prd to tasks".
---

# PRD to Tasks

Convert `$1/PRD.md` into `$1/tasks.json` -- a machine-readable backlog that a Ralph loop can drive off. Tasks must be small, independently verifiable, and ordered so that foundation comes first.

$1 is the Progress Directory -- an absolute path passed as the first argument when the skill is invoked (e.g. `/prd-to-tasks /path/to/progress`). All input and output files live there. The Working Directory root is separate.

## Process

1. Read `$1/PRD.md`. If it doesn't exist, ask the user where the PRD lives.

2. If `UBIQUITOUS_LANGUAGE.md` exists in the Working Directory root, read it and use its vocabulary when writing task descriptions.

3. Decompose the PRD's user stories and implementation decisions into tasks. Each task should:

   - Take no more than roughly 30-90 minutes of focused work (one Ralph iteration).
   - Have verifiable acceptance criteria that a developer or QA session could check without reading the code.
   - Be as independent as reasonable -- if a task genuinely depends on another, note that in its `context.notes` (e.g. `"depends on #3"`), do not introduce a separate field.

4. Write `$1/tasks.json`. Overwrite any existing file without asking.

5. Print a one-line confirmation and the count: `Wrote N tasks to $1/tasks.json`. Do not list them -- the user can read the file.

## Task Schema

```json
[
  {
    "id": 1,
    "category": "schema",
    "description": "Rename tasks.json field done to passes across the engine",
    "acceptance_criteria": [
      "Engine checks passes when terminating iterate:tasks phases",
      "All bundled fixtures use passes, not done",
      "Test suite compiles and passes"
    ],
    "effort": "low",
    "passes": false
  }
]
```

## Field Rules

- `id`: sequential integer starting at `1`. If a `tasks.json` already exists with tasks, continue the numbering.
- `category`: short tag -- typical values: `schema`, `ui`, `engine`, `prompt`, `infrastructure`, `bug`, `docs`.
- `description`: one imperative sentence using domain language. No file paths. No line numbers.
- `acceptance_criteria`: bulleted, independently verifiable, at most 5 items.
- `effort`: `"low"` | `"medium"` | `"high"` -- rough sizing.
- `passes`: always starts `false`. Ralph flips it to `true` when the task's acceptance criteria are met.

## Ordering

List tasks in the order Ralph should tackle them:

1. Schema / infrastructure changes (anything later tasks depend on)
2. Engine-level work
3. Prompt authoring
4. UI surface
5. Documentation / polish

Bugs discovered later get appended to the end of the list by the `qa` skill.

## Rules

- **Prefer many thin tasks over few thick ones.** Easier for Ralph to complete in one iteration, easier to verify.
- **No file paths or line numbers in descriptions or acceptance criteria.** They go stale.
- **Do not include "write tests for X" as a separate task** unless testing is a large body of work on its own. Assume Ralph writes tests alongside the implementation task.
- **Do not break the PRD down into more than ~15 tasks** in one pass. If the PRD is huge, flag this to the user -- the PRD probably needs to be split into two features.
