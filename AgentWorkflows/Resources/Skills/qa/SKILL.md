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
