# AgentWorkflows — Agent Guidelines

## Overview
AgentWorkflows is a native macOS SwiftUI application that orchestrates AI-driven feature development through a structured workflow loop (Plan → Build → Verify). It manages sessions, runs skills via CLI agents, and provides a rich UI for inspection and control.

## Required Skills
The following Claude Code skills must be installed for this tool to function:
- `/grill-me` — Interview the user to hone plans and requirements
- `/ubiquitous-language` — Extract a DDD-style glossary into `UBIQUITOUS_LANGUAGE.md`
- `/to-prd` — Convert conversation context into a `PRD.md`
- `/prd-to-tasks` — Decompose a PRD into a structured `tasks.json` backlog
- `/ralph` — Run one iteration of the Ralph loop (read backlog, pick task, implement, commit)
- `/qa` — Interactive QA session; appends bug reports as tasks to `tasks.json`

## Supported CLI Agents / SDKs
This tool is designed for vendor flexibility and intentionally avoids AI vendor lock-in. Agent Skills is an open standard (SKILL.md format) adopted by 16+ tools — skills work across agents without modification.

Supported or planned agents for both Terminal (planning) and Iterations (Ralph loop) phases:
- **Claude Code** (`claude`) — primary supported agent
- **Codex** (`codex`) — supported via `CodexProcessRunner`
- **Pi** — planned
- **Gemini CLI** — planned
- **Mistral** — planned
- **OpenCode** — planned
- **Cursor** — planned

Model selection per workflow step is a core feature — agents working on this codebase should preserve and extend the per-step model configurability rather than hardcoding any single provider.

## Application Tabs
| Tab | Purpose |
|-----|---------|
| **Terminal** | Direct interactive AI session — used to generate `PRD.md`, `UBIQUITOUS_LANGUAGE.md`, `tasks.json`, etc. via skills |
| **Iterations** | Shows each task and its iteration history; auto-cancels after 3 failed attempts (stall detection) |
| **Files** | Viewer for files produced by the tool (MD, JSON, XML with syntax coloring) |
| **Diff** | Shows what changed in each iteration (git diff per iteration) |
| **Log** | Execution and debug log for detecting issues |

## Session Model
- Each session is identified by a **UUID** — multiple sessions per repo are supported
- Session artifacts live in `.aw-cache/{sessionID}/` (gitignored, ephemeral)
- Committed metadata lives in `.aw/` (settings, ubiquitous language)
- Per-repo configuration: `.aw/settings.json`

## Key Artifacts Per Session
| File | Purpose |
|------|---------|
| `PRD.md` | Product requirements — created by `/to-prd` |
| `tasks.json` | Structured backlog — created by `/prd-to-tasks` |
| `UBIQUITOUS_LANGUAGE.md` | Shared domain glossary — created by `/ubiquitous-language` |
| `progress.txt` | Append-only log of iteration summaries |
| `ralph-logs/iter-N.log` | Per-iteration detailed log |

## UX Principles
Shortcuts and user experience are first-class concerns. Key UX features to preserve and extend:
- Open session in Finder
- Open session in Terminal (configurable: Ghostty, iTerm, default Terminal)
- Open session in editor
- Quick rename session
- Quick delete session
- Open diff viewer (external, configurable)

## Testing
**Do not write UI tests.** Unit and integration tests are appropriate; UI/snapshot tests are not used in this project.

## Architecture Notes
- `Engine/` — workflow orchestration, process runners, skill management, signal watching
- `Models/` — data structures (Session, Workflow, Settings, etc.)
- `Storage/` — persistence, file I/O, session registry
- `Views/` — SwiftUI UI layer (no UIKit)
- Skills ship bundled inside the app at `AgentWorkflows/Resources/Skills/` and are installed to the user's `.claude/` skills directory
