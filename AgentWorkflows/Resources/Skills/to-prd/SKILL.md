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
