---
name: ralph
description: Run one iteration of the Ralph loop -- read the backlog, pick the next incomplete task, implement it, commit, flip its passes flag, and append to the progress log. Use when the user invokes Ralph manually, or when a workflow runner drives the loop.
---

# Ralph

One iteration of the Ralph loop. You are called repeatedly until every task in `tasks.json` has `passes: true`. Every iteration starts with fresh context -- assume you remember nothing. The files are the memory.

$1 is the Progress Directory -- an absolute path passed as the first argument when the skill is invoked (e.g. `/ralph /path/to/progress`). All backlog and progress files live there. The Working Directory root is the repo root (separate from $1).

## Process

### 1. Read state

Read each of these files if they exist:

- `$1/PRD.md` -- the feature specification (stable, don't modify).
- `UBIQUITOUS_LANGUAGE.md` in the Working Directory root -- project vocabulary (stable, don't modify).
- `$1/tasks.json` -- the backlog (you will mutate this).
- `$1/progress.txt` -- memory from previous iterations (you will append to this).

If `$1/progress.txt` doesn't exist, create it empty. If `$1/tasks.json` doesn't exist, stop and print an error: Ralph requires a backlog.

### 2. Pick the next task

From `$1/tasks.json`, find the first item where `passes` is `false`. This is your one task for this iteration. Do NOT work on multiple tasks.

If every item already has `passes: true`, stop -- the loop has nothing left to do.

### 3. Implement

Do the task. All of it. This includes:

- Writing or modifying code until every entry in the task's `acceptance_criteria` holds.
- Writing or updating tests that cover the acceptance criteria.
- Running the test suite. If the project has a type-checker or linter, run those too.
- Using the project's domain language (`UBIQUITOUS_LANGUAGE.md`) when naming things. If you introduce a new domain term, note it in `$1/progress.txt` so the user can add it to `UBIQUITOUS_LANGUAGE.md` later.

### 4. Commit

Create a git commit with a message that:

- Starts with the task's `category` in brackets: `[schema]`, `[ui]`, `[engine]`, etc.
- Contains a one-line summary of what changed (imperative mood).
- References the task id in parens at the end: `(task #N)`.

Example: `[schema] Rename tasks.json field done to passes (task #1)`

Stage only the files you changed. Do not `git add -A`.

### 5. Mutate tasks.json

Flip the current task's `passes` from `false` to `true`. Leave every other task unchanged. Do not reorder, delete, or add tasks. Write the updated `$1/tasks.json`.

### 6. Append to progress.txt

Append a short paragraph to `$1/progress.txt` describing:

- The task id at the start: `Task #N:`
- What you did (one sentence).
- Any surprising or non-obvious decision you made.
- Anything the next iteration should know (e.g. "task #N+1 is now unblocked", "touched schema -- later tasks must migrate").

Keep it terse. Two to five sentences. No bullet lists.

Example:

```
Task #1: Renamed done to passes across the engine, bundled tasks.json fixtures, and the iterate:tasks terminator. Engine now checks passes when deciding phase termination. Existing sessions created before this change will have old field names -- migration is task #7.
```

### 7. Stop

Do not pick up another task. Exit cleanly so the loop runner can invoke the next iteration.

## Rules

- **One task per iteration. Always.** Even if a task is tiny, don't chain.
- **Do not edit `$1/PRD.md` or `UBIQUITOUS_LANGUAGE.md`.** These are stable inputs; they were authored before Ralph started.
- **Always commit, always append to $1/progress.txt.** A silent iteration leaves no audit trail.
- **If the task is genuinely blocked** (acceptance criteria can't be met because of missing dependencies, unclear spec, or an external system you can't reach), leave `passes` as `false`, do NOT commit, and append a paragraph to `$1/progress.txt` explaining the blocker. The next iteration (or the user) will see it.
- **If tests fail and you can't fix them in this iteration**, revert your in-progress changes, leave `passes: false`, and append the failure mode to `$1/progress.txt`. Do not commit broken code.
- **Never mark `passes: true` when the acceptance criteria aren't met.** This corrupts the signal the loop relies on for termination and misleads the QA phase.
- **Never skip a task** by flipping `passes: true` without doing the work. If a task is obsolete, stop and tell the user -- the backlog needs pruning, not silent skipping.
