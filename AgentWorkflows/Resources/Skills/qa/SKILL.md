---
name: qa
description: Interactive QA session where the user reports bugs conversationally and the agent appends them to tasks.json. Explores the codebase in the background for context and domain language. Use when the user wants to report bugs, do QA, file issues conversationally, or mentions "QA session".
---

# QA Session

Run an interactive QA session. The user describes problems; you clarify, explore the codebase for context, and append bug tasks to `$1/tasks.json` for a Ralph loop (or the user) to pick up.

$1 is the Progress Directory — an absolute path passed as the first argument (e.g. `/qa /path/to/progress`). All backlog files live there. The Working Directory root is the repo root.

## Before the session starts

### 0. Generate a testing guide

Before asking the user anything, read `$1/tasks.json` (if it exists) and run `git log --oneline -20` to understand what was recently implemented. Spawn an Explore agent in the background to read the relevant areas of the codebase.

Once you have enough context, output a numbered step-by-step testing guide — the concrete actions the user should take to exercise what was built. Each step should be a single action (navigate to X, click Y, enter Z). Cover the main flow first, then edge cases.

Format:

```
## Testing Guide

### <Feature or area name>
1. <action>
2. <action>
...

### <Next area if applicable>
1. <action>
...
```

Then say: "Work through these steps and tell me what you find. Report anything that looks wrong."

---

## For each issue the user raises

### 1. Listen and lightly clarify

Let the user describe the problem in their own words. Ask **at most 2–3 clarifying questions** focused on:

- What they expected vs what actually happened
- Steps to reproduce (if not obvious)
- Whether it's consistent or intermittent

Do NOT over-interview. If the description is clear enough to file, move on.

### 2. Explore the codebase in the background

While talking to the user, kick off an Explore agent in the background. The goal is NOT to find a fix — it's to:

- Learn the domain language (check `UBIQUITOUS_LANGUAGE.md` in the repo root)
- Understand what the feature is supposed to do
- Identify the user-facing behavior boundary

This context improves the task — but the task itself should NOT reference files, line numbers, or implementation details.

### 3. Assess scope: single task or breakdown?

Before appending, decide: **single task** or **breakdown**?

Break down when:

- The fix spans multiple independent areas (e.g. "the form validation is wrong AND the success message is missing AND the redirect is broken")
- Concerns are separable enough for parallel work
- Multiple distinct failure modes or symptoms

Keep as a single task when:

- It's one behavior that's wrong in one place
- All symptoms share the same root behavior

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

- **Prefer thin tasks over thick ones** — each independently fixable and verifiable.
- If task B can't be verified until task A is fixed, note it in B's `context.notes` (e.g. `"blocked until #<A>"`). Don't add a `blocked_by` field — context notes are enough.
- Append all of them in dependency order so later tasks can reference earlier IDs in their notes.

Don't ask the user to review before writing — just append and confirm.

Write the updated `$1/tasks.json`. Print: `Appended task(s): #N, #N+1, ...` and a one-line summary of each.

### 5. Rules for all task bodies

- **No file paths or line numbers** — they go stale.
- **Use the project's domain language** (check `UBIQUITOUS_LANGUAGE.md` in the repo root if it exists).
- **Describe behaviors, not code** — "the sync service fails to apply the patch" not "applyPatch() throws on line 42".
- **Reproduction steps are mandatory** — if you can't determine them, ask before appending.
- **Keep it concise** — a developer (or Ralph) should read the task in 30 seconds.

After appending, ask: "Next issue, or are we done?"

### 6. Continue the session

Keep going until the user says they're done. Each task is independent — don't batch them.
