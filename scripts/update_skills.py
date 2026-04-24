#!/usr/bin/env python3
"""One-shot script to update the four Ralph skills to use $1 as progress directory."""

import os

SKILLS_DIR = os.path.expanduser("~/.claude/skills")

TO_PRD = """\
---
name: to-prd
description: Turn the current conversation context into a PRD and write it to PRD.md in the progress directory. Use when user wants to create a PRD from the current context.
---

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT interview the user -- just synthesize what you already know.

$1 is the Progress Directory -- an absolute path passed as the first argument when the skill is invoked (e.g. `/to-prd /path/to/progress`). All output files go there. The Working Directory root is separate and is where `UBIQUITOUS_LANGUAGE.md` lives.

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already.

2. If `UBIQUITOUS_LANGUAGE.md` exists in the Working Directory root, read it and use its vocabulary consistently when writing the PRD.

3. Sketch out the major modules you will need to build or modify to complete the implementation. Actively look for opportunities to extract deep modules that can be tested in isolation.

A deep module (as opposed to a shallow module) is one which encapsulates a lot of functionality in a simple, testable interface which rarely changes.

Check with the user that these modules match their expectations. Check with the user which modules they want tests written for.

4. Write the PRD to `$1/PRD.md` using the template below. Overwrite an existing `PRD.md` without asking.

<prd-template>

# PRD: <feature name>

## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the format of:

1. As an <actor>, I want a <feature>, so that <benefit>

<user-story-example>
1. As a mobile bank customer, I want to see balance on my accounts, so that I can make better informed decisions about my spending
</user-story-example>

This list of user stories should be extremely extensive and cover all aspects of the feature.

## Implementation Decisions

A list of implementation decisions that were made. This can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behavior, not implementation details)
- Which modules will be tested
- Prior art for the tests (i.e. similar types of tests in the codebase)

## Out of Scope

A description of the things that are out of scope for this PRD.

## Further Notes

Any further notes about the feature.

</prd-template>

5. After writing, print a one-line confirmation: `PRD written to $1/PRD.md`. Do not summarize the PRD contents -- the user can read the file.
"""

PRD_TO_TASKS = """\
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
"""

RALPH = """\
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
"""

QA = """\
---
name: qa
description: Interactive QA session where user reports bugs or issues conversationally, and the agent appends them as tasks to tasks.json. Explores the codebase in the background for context and domain language. Use when user wants to report bugs, do QA, file issues conversationally, or mentions "QA session".
---

# QA Session

Run an interactive QA session. The user describes problems they're encountering. You clarify, explore the codebase for context, and append structured bug tasks to `$1/tasks.json` so a Ralph loop (or the user) can pick them up.

$1 is the Progress Directory -- an absolute path passed as the first argument when the skill is invoked (e.g. `/qa /path/to/progress`). All backlog files live there. The Working Directory root is the repo root.

## For each issue the user raises

### 1. Listen and lightly clarify

Let the user describe the problem in their own words. Ask **at most 2-3 short clarifying questions** focused on:

- What they expected vs what actually happened
- Steps to reproduce (if not obvious)
- Whether it's consistent or intermittent

Do NOT over-interview. If the description is clear enough to file, move on.

### 2. Explore the codebase in the background

While talking to the user, kick off an Agent (subagent_type=Explore) in the background to understand the relevant area. The goal is NOT to find a fix -- it's to:

- Learn the domain language used in that area (check `UBIQUITOUS_LANGUAGE.md` in the Working Directory root)
- Understand what the feature is supposed to do
- Identify the user-facing behavior boundary

This context helps you write a better task -- but the task itself should NOT reference specific files, line numbers, or internal implementation details.

### 3. Assess scope: single task or breakdown?

Before appending, decide whether this is a **single task** or needs to be **broken down** into multiple tasks.

Break down when:

- The fix spans multiple independent areas (e.g. "the form validation is wrong AND the success message is missing AND the redirect is broken")
- There are clearly separable concerns that different people (or Ralph iterations) could work on in parallel
- The user describes something that has multiple distinct failure modes or symptoms

Keep as a single task when:

- It's one behavior that's wrong in one place
- The symptoms are all caused by the same root behavior

### 4. Append to tasks.json

Read `$1/tasks.json`. If it doesn't exist, create it as an empty array `[]`.

Determine the next `id`: one higher than the current maximum `id` in the file (or `1` if empty).

For each bug, append a task object with this shape:

```json
{
  "id": <next-id>,
  "category": "bug",
  "description": "<one-sentence description of the wrong behavior, user-perspective, using project domain language>",
  "acceptance_criteria": [
    "<expected behavior restored>",
    "<any regression tests covering this case>"
  ],
  "effort": "low" | "medium" | "high",
  "passes": false,
  "context": {
    "what_happened": "<observed behavior in plain language>",
    "what_expected": "<expected behavior>",
    "steps_to_reproduce": ["<step 1>", "<step 2>", "..."],
    "notes": "<any extra context from background exploration -- use domain language, don't cite files>"
  }
}
```

When breaking down one report into multiple tasks:

- **Prefer many thin tasks over few thick ones** -- each should be independently fixable and verifiable.
- If task B genuinely can't be verified until task A is fixed, note this in B's `context.notes` (e.g. `"blocked until #<A>"`). Do NOT introduce a separate `blocked_by` field -- context notes are enough.
- Append all of them in dependency order so later tasks can reference earlier IDs in their notes.

Do NOT ask the user to review the task JSON before writing -- just append and confirm.

Write the updated `$1/tasks.json`. Print: `Appended task(s): #N, #N+1, ...` and a one-line summary of each.

### 5. Rules for all task bodies

- **No file paths or line numbers** -- these go stale.
- **Use the project's domain language** (check `UBIQUITOUS_LANGUAGE.md` in the Working Directory root if it exists).
- **Describe behaviors, not code** -- "the sync service fails to apply the patch" not "applyPatch() throws on line 42".
- **Reproduction steps are mandatory** -- if you can't determine them, ask the user before appending.
- **Keep it concise** -- a developer (or Ralph) should be able to read the task in 30 seconds.

After appending, ask: "Next issue, or are we done?"

### 6. Continue the session

Keep going until the user says they're done. Each task is independent -- don't batch them.
"""

files = {
    "to-prd/SKILL.md": TO_PRD,
    "prd-to-tasks/SKILL.md": PRD_TO_TASKS,
    "ralph/SKILL.md": RALPH,
    "qa/SKILL.md": QA,
}

for rel, content in files.items():
    path = os.path.join(SKILLS_DIR, rel)
    with open(path, "w") as f:
        f.write(content)
    print(f"wrote {path}")
