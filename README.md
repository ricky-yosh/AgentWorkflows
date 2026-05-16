# AgentWorkflows

A native macOS application for AI-driven feature development. It guides you from initial idea through a structured loop — plan, build, verify — using your choice of AI agent.

Inspired by the [Ralph loop](https://github.com/mattpocock/skills) workflow.

## How it works

1. **Plan** — Use the Terminal tab to run skills like `/grill-me`, `/to-prd`, and `/prd-to-tasks`. These produce a `PRD.md` and a `tasks.json` backlog through a conversational session with your AI agent.
2. **Build** — The app runs the `/ralph` skill in a loop, picking tasks one at a time, implementing them, and committing. Each iteration is tracked.
3. **Verify** — Review what changed, run QA with `/qa`, and ship.

## Features

- **No vendor lock-in** — Switch between Claude Code, Codex, Gemini CLI, OpenCode, Cursor, Pi, Mistral, and more. Each workflow phase (Plan, Build, Verify) can use a different agent.
- **Multiple sessions** — Run multiple feature sessions against the same repo simultaneously. Planning sessions can run in parallel; loop execution is your responsibility to coordinate.
- **Session artifacts** — Each session produces `PRD.md`, `tasks.json`, `UBIQUITOUS_LANGUAGE.md`, and per-iteration logs, all scoped to a UUID session directory.
- **Shared vocabulary** — `UBIQUITOUS_LANGUAGE.md` captures domain terminology so nothing gets lost between developers or between developers and AI agents.

## Tabs

| Tab | Purpose |
|-----|---------|
| **Terminal** | Interactive AI session for planning — runs skills to produce PRD, tasks, and glossary |
| **Iterations** | Task list with per-task iteration history; stalled tasks are flagged automatically |
| **Files** | Read-only viewer for session artifacts (Markdown, JSON, XML) |
| **Diff** | Per-iteration git diff to see exactly what each loop iteration changed |
| **Log** | Execution log for debugging |

## Verify your AI tools

Run these commands from any terminal to confirm each supported SDK/CLI is installed, authenticated, and returning output before using it in the app.

**Claude Code**
```bash
claude -p --permission-mode acceptEdits --model sonnet --output-format stream-json --verbose "Say hello from Claude Code in one short sentence."
```

Ralph-style command used by the build loop:
```bash
PROGRESS_DIR="$(mktemp -d)"
claude -p --permission-mode acceptEdits --model sonnet --output-format stream-json --verbose --effort low "/ralph $PROGRESS_DIR"
```

**Codex**
```bash
codex exec --json "Say hello from Codex in one short sentence."
```

Ralph-style command used by the build loop:
```bash
PROGRESS_DIR="$(mktemp -d)"
codex exec --dangerously-bypass-approvals-and-sandbox -c model_reasoning_effort=low --json "\$ralph $PROGRESS_DIR"
```

**Pi**
```bash
pi -p --mode json "Say hello from Pi in one short sentence."
```

Ralph-style command used by the build loop:
```bash
PROGRESS_DIR="$(mktemp -d)"
pi -p --mode json "/skill:ralph $PROGRESS_DIR"
```

**OpenCode**
```bash
opencode run --format json "Say hello from OpenCode in one short sentence."
```

Ralph-style command used by the build loop:
```bash
PROGRESS_DIR="$(mktemp -d)"
opencode run --format json --dangerously-skip-permissions "/ralph $PROGRESS_DIR"
```

For the simple hello commands, any short assistant response confirms the SDK/CLI is working. The Ralph-style commands require the corresponding skill to be installed and a valid progress directory containing the workflow artifacts, so they are mainly useful when debugging the app's build-loop subprocess behavior.

## Required Skills

The following [Agent Skills](https://agentskills.io) must be installed:

| Skill | Purpose |
|-------|---------|
| `/grill-me` | Interview to hone plans and requirements |
| `/ubiquitous-language` | Extract shared domain glossary |
| `/to-prd` | Turn conversation into a `PRD.md` |
| `/prd-to-tasks` | Decompose PRD into `tasks.json` backlog |
| `/ralph` | Run one iteration of the build loop |
| `/qa` | File bugs conversationally into `tasks.json` |

Skills follow the open Agent Skills standard and work across all supported agents.

## Shortcuts

- **Open in Finder** — jump to the session directory
- **Open in Terminal** — configurable (Ghostty, iTerm, Terminal.app)
- **Open in Editor** — open session files in your editor
- **Rename session** — right-click the session in the sidebar
- **Delete session** — right-click the session in the sidebar
- **Open diff viewer** — configurable external diff tool

## Installation

Download the latest `AgentWorkflows.zip` from [Releases](../../releases), unzip, and drag `AgentWorkflows.app` to `/Applications`.

Since the app is unsigned, clear the quarantine flag before opening:

```bash
xattr -cr AgentWorkflows.app
```

## Session Storage

- Session metadata: `.aw/` (committed to git)
- Session artifacts: `.aw-cache/{uuid}/` (gitignored, ephemeral)
- App-level registry: `~/Library/Application Support/AW/sessions.json`
