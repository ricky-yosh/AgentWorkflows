---
name: ralph
description: Run one iteration of the Ralph loop -- read the backlog, pick the next runnable task, implement it, commit it, and flip its passes flag. Use when the user invokes Ralph manually, or when a workflow runner drives the loop.
---

# Ralph

One iteration of the Ralph loop. You are called repeatedly until every task in `tasks.json` has `passes: true`. Every iteration starts with fresh context -- assume you remember nothing. The files are the memory.

`$1` is the Progress Directory -- the first argument (for example, `/ralph /path/to/progress`). All backlog and progress files live there. The Working Directory root is the repo root (separate from `$1`).

## Process

### 1. Read state

Read each of these files if they exist:

- `$1/PRD.md` -- the feature specification (stable, don't modify).
- `.aw/CONTEXT.md` in the Working Directory root -- project vocabulary (stable, don't modify).
- Every Markdown file in `.aw/adr/` in lexical order -- architectural decisions (stable, don't modify unless this iteration resolves a HITL task).
- `$1/tasks.json` -- the backlog (you will mutate this only when the current task is completed).

If `$1/tasks.json` doesn't exist, stop and print an error: Ralph requires a backlog.

### 2. Pick the next runnable task

From `$1/tasks.json`, inspect tasks in order and find the first item where `passes` is `false` and every id in `blocked_by` has already passed. `blocked_by` defaults to `[]` if absent. `type` defaults to `"AFK"` if absent.

If a task has unmet `blocked_by` entries, it is not runnable yet:

- For an AFK task, skip it for this iteration and keep scanning for the next unblocked task.
- For a HITL task, report the unmet blocker ids before considering whether `resolution` is present. Keep scanning for an unblocked runnable task.

If every item already has `passes: true`, stop -- the loop has nothing left to do.

If unfinished tasks remain but all are blocked, stop and print the blocked task ids and their unmet blocker ids. Do not commit. Do not mutate `tasks.json`.

### 3. Handle HITL tasks

If the runnable task has `type: "HITL"` and `resolution` is empty, missing, or only whitespace:

- Print the task id, description, acceptance criteria, and the decision needed.
- Stop cleanly.
- Do not write an ADR.
- Do not mutate `tasks.json`.
- Do not commit.

If the runnable task has `type: "HITL"` and `resolution` is populated:

- Write an ADR to `.aw/adr/` capturing the decision. Create the directory if needed.
- The ADR must include the task id, context from the task description, the resolution, and consequences or follow-up work when known.
- Flip only this task's `passes` from `false` to `true`.
- Commit the ADR and `$1/tasks.json`.
- Stop. Do not implement or pick up another task.

### 4. Implement AFK tasks

Do the runnable AFK task. All of it. This includes:

- Writing or modifying code until every entry in the task's `acceptance_criteria` holds.
- Writing or updating tests that cover the acceptance criteria.
- Running the test suite. If the project has a type-checker or linter, run those too.
- Using the project's domain language from `.aw/CONTEXT.md` when naming things.
- Respecting architectural decisions from `.aw/adr/`.

### 5. Mutate tasks.json

When the runnable task is complete and verified, flip only that task's `passes` from `false` to `true`. Leave every other task unchanged. Do not reorder, delete, or add tasks.

### 6. Commit

Create a git commit with a message that:

- Starts with the task's `category` in brackets: `[schema]`, `[ui]`, `[engine]`, etc.
- Contains a one-line summary of what changed (imperative mood).
- References the task id in parens at the end: `(task #N)`.

Example: `[schema] Rename tasks.json field done to passes (task #1)`

Stage only the files you changed. Do not `git add -A`.

### 7. Stop

Do not pick up another task. Exit cleanly.

## Rules

- **One task per iteration. Always.** Even if a task is tiny, don't chain.
- **Do not edit `$1/PRD.md`, `.aw/CONTEXT.md`, or existing files in `.aw/adr/`.** These are stable inputs. The only ADR write allowed is a new ADR for a resolved HITL task.
- **Always commit completed work.** A silent completed iteration leaves no audit trail.
- **If the task is genuinely blocked** (acceptance criteria can't be met because of missing dependencies, unclear spec, or an external system you can't reach), leave `passes` as `false`, do NOT commit, and stop with a clear explanation of the blocker so the user can see it.
- **If tests fail and you can't fix them in this iteration**, revert your in-progress changes, leave `passes: false`, and stop with the failure mode explained. Do not commit broken code.
- **Never mark `passes: true` when the acceptance criteria aren't met.** This corrupts the termination signal and misleads the QA phase.
- **Never skip a task** by flipping `passes: true` without doing the work. If a task is obsolete, stop and tell the user -- the backlog needs pruning, not silent skipping.
