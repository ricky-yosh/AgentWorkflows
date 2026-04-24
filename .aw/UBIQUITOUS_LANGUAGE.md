# Ubiquitous Language

## Repo layout

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Metadata Directory** | `{workingDirectory}/.aw/` — committed, git-tracked AW artifacts that humans deliberately edit. Holds the **Glossary** and **Per-Repo Settings**. Stable across sessions; never per-session. | `.aw`, config dir |
| **Cache Directory** | `{workingDirectory}/.aw-cache/` — gitignored, ephemeral AW state. Parent of every **Session Directory**. Regenerable; safe to wipe. | `.aw-cache`, session cache, scratch dir |

## Session lifecycle

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Session** | A single instance of the Ralph feature-development loop bound to a **Working Directory** and a **Session Directory**. | Project, run |
| **Working Directory** | The user's repo root that Claude Code edits — the cwd of the **Terminal Engine**. | Repo, project root, cwd |
| **Session Directory** | Per-session storage at `{workingDirectory}/.aw-cache/{sessionID}/`, where `sessionID` is the **Session**'s UUID. Holds every per-session artifact: **State File**, **Tasks File**, **Progress Log**, **Events Log**, **Iteration Logs**, **PRD**. Never renamed. | Progress dir, session folder, cache dir |
| **Progress Directory** | Synonym for **Session Directory**. The `$1` argument passed to the `/ralph` skill and the `{progress-path}` **Template Variable** both resolve to this path. | Cache dir, session cache |
| **Session Registry** | Central pointer file at `~/Library/Application Support/AW/sessions.json`. A JSON array of `{id, name, workingDirectory, workflowName}` — one entry per **Session** the user has ever created across all **Working Directories**. Mutable state (phase/step/completions) is *not* stored here. Updated only on **Session** create, delete, and rename. | Session index, session list |
| **Seed** | One- or two-sentence user intent captured before Play to prime the opening `/grill-me` step. Consumed at first prompt injection; not re-prompted after `plan-grill-me` completes. | Intent, brief |

## Workflow structure

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Workflow** | A named tree of **Phases** and **Steps**. The app ships exactly one: `Workflow.ralph`. | Pipeline, recipe |
| **Phase** | A named group of **Steps** inside a **Workflow**. `Workflow.ralph` defines `Plan`, `Build`, `Verify`. | Stage |
| **Step** | The atomic unit the **Workflow Engine** executes. Has a type: `prompt`, `clear`, `pause`, `break`, `comment`, `loop`, `iterate_tasks`. | Task (ambiguous — see below) |
| **Iterate-Tasks Step** | A container **Step** whose nested children are executed repeatedly by the **Loop Driver** until `IterateTasksTerminator` decides terminate. | Loop step |
| **Iteration** | One pass through an **Iterate-Tasks Step**'s nested children, driven by the **Loop Driver**. One **Iteration** equals one `claude -p /ralph` invocation. | Loop cycle, round |
| **Pause Step** | A **Step** type that halts the **Workflow Engine** until the user hits Continue. | Wait, review gate |

## Execution

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Workflow Engine** | Orchestrator that walks the **Workflow** tree, injects prompt text into the **Terminal Engine**, and advances on **Signal File** events or child-engine completion. | Runner, executor |
| **Loop Driver** | Drives **Iterations** inside an **Iterate-Tasks Step**. Reads `tasks.json` between **Iterations**, delegates termination to `IterateTasksTerminator`, detects **Stall**. | Iterator, loop runner |
| **Terminal Engine** | The PTY-backed process bound to the session's terminal view. Runs `claude` with cwd set to the **Working Directory** for the session's lifetime. Receives prompt injections. | Terminal, shell, PTY |
| **Signal File** | Empty file at `{sessionDirectory}/step-complete-{sessionID}` whose appearance tells the **Workflow Engine** that the current **Step** finished. Written by the agent in response to the signal footer. | Step-complete file, sentinel |
| **Signal Footer** | Appended instructions (produced by `PromptSignalFooterWrapper`) telling the agent where to write the **Signal File** when a **Step**'s work is done. Wrapped onto every CLI prompt injection. | Footer, completion instruction |
| **Template Variable** | Placeholder in prompt text resolved by `TemplateResolver` before injection: `{progress-path}` → the **Session Directory**, `{signal-path}` → the **Signal File** path. | Macro, substitution |
| **Process Runner** | Seam that spawns one CLI subprocess per **Iteration** on behalf of the **Loop Driver**, streams stdout through its **Event Stream Decoder**, tees raw lines to **Iteration Logs**, and reports exit. One **Process Runner** implementation per **CLI Preset** (`ClaudeProcessRunner`, future `CodexProcessRunner`, future `PiProcessRunner`); `ProcessRunnerFactory` selects. Distinct from the **Terminal Engine**, which owns the interactive PTY for non-loop **Steps**. | Subprocess runner, headless runner |
| **Subprocess Runner** | Planned internal helper that factors the shared spawn/pipe/termination plumbing out of each **Process Runner** implementation. Takes `(arguments, decoder)` so each **Process Runner** becomes a thin wrapper. Introduced to eliminate duplication between `ClaudeProcessRunner` and a future `CodexProcessRunner`. | Spawn helper, process helper |
| **Event Stream Decoder** | Per-CLI parser that turns one line of subprocess stdout into zero or more **Iteration Events**. Claude's implementation is `StreamJsonDecoder`; Codex and Pi will each ship their own. No shared protocol exists yet — deferred until three examples are in hand. | Stream parser, line parser |
| **Iteration Event** | The canonical parsed-event enum (`IterationEvent`) the **Loop Driver** consumes: `sessionStarted`, `assistantText`, `toolUse`, `toolResult`, `iterationFinished`. CLI-agnostic — each **Event Stream Decoder** maps its CLI's native JSONL into this shape. | Parsed event, engine event |

## Ralph loop

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Ralph Loop** | The full `Workflow.ralph` execution: `Plan` phase (`/grill-me`, `/ubiquitous-language`, `/to-prd`, `/prd-to-tasks`, review) → `Build` phase (iterate `/ralph`) → `Verify` phase (`/qa`, review). | Ralph workflow |
| **Backlog** | The ordered list of work inside `tasks.json`. The **Loop Driver** picks the first entry with `passes: false` per **Iteration**. | Task list |
| **Task** | One entry in the **Backlog**, with `passes` flag, acceptance criteria, and effort. Not to be confused with **Step**. | Ticket, item |
| **Passes** | Boolean on a **Task** indicating it's verifiably complete. All-passes is the primary **Loop** termination condition. | Done (historical; renamed) |
| **Max Iterations** | Per-**Iterate-Tasks Step** cap on **Iteration** count. Complements **Stall Detection**. Hardcoded at 25 in `Workflow.ralph`. | Cap, limit |
| **Stall Detection** | **Loop Driver** heuristic: three consecutive **Iterations** with no change in the **Passes** signature → session state `.stalled`. | Stuck check |
| **Convergence** | The happy-path **Ralph Loop** terminal condition: every **Task** has `passes: true`, triggering advance from Build to Verify. | Completion |

## Effort

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Effort** | Per-**Task** reasoning-budget knob passed to `claude -p` as `--effort <level>`. Sourced from the `effort` field on the current **Task** in the **Tasks File** and applied once per **Iteration**. | Thinking budget, reasoning level |
| **Effort Level** | One of `low`, `medium`, `high` — the three **Effort** values AW exposes. Represented in Swift as the `Effort` enum, whose `rawValue` is the exact `--effort` argv value. | Effort tier, difficulty |
| **Effort Ceiling** | The `high` cap AW enforces on **Effort Level**. Values outside AW's range (`xhigh`, `max`, or any future CLI-only level) clamp to `high` at resolution time — AW deliberately refuses to surface the CLI's upper tiers. | Max effort |
| **Effort Default** | The `medium` fallback applied when a **Task** lacks `effort`, carries an unrecognized value, or `tasks.json` is unreadable. Keeps existing backlogs working unchanged when the feature lands. | Default level |

## Skills and artifacts

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Skill** | A Claude Code slash-command authored as `{name}/SKILL.md` under the **Skills Directory**. The **Ralph Loop** depends on six **Required Skills**: `/grill-me`, `/ubiquitous-language`, `/to-prd`, `/prd-to-tasks`, `/ralph`, `/qa`. | Command, prompt |
| **Skills Directory** | `~/.claude/skills/` — the user-global location Claude Code reads **Skills** from. Claude-specific; parallel to **Codex Skills Directory**. The **Presence Check** probes this path, and `.claude` is the default **Skill Target** for **Skill Install**. | User skills dir, skills folder |
| **Codex Skills Directory** | `~/.codex/skills/` — the user-global location Codex reads **Skills** from. Same layout as the **Skills Directory** (dir-per-skill, `SKILL.md` with required YAML frontmatter) — no transform, no frontmatter stripping. The **Skill Installer** writes the same bytes here when `.codex` is a selected **Skill Target**. | Codex skills dir |
| **Skill Target** | An enum value selecting which CLI's skills directory a **Skill Install**, **Skill Update**, or **Skill Removal** action writes to: `.claude` (→ **Skills Directory**) or `.codex` (→ **Codex Skills Directory**). One **Skill Bundle**, many **Skill Targets**. | Install destination, target cli |
| **Skill Invocation** | The CLI-level syntax a **Skill** is triggered by inside a prompt. Claude uses `/{name}`; Codex uses `${name}` (or `/{name}`, less reliably). The **Skill** file on disk is the same shape for both CLIs; only the in-prompt prefix differs. | Command syntax, slash command |
| **Required Skills** | The six **Skills** enumerated by `PresenceChecker.requiredSkills`. Load-bearing for the **Ralph Loop**; the **Presence Check** verifies all six and the **Skill Bundle** ships exactly this set. | Core skills, mandatory skills |
| **Coordination Artifact** | A file produced or consumed by **Skills** during a **Ralph Loop**. Per-session artifacts live in the **Session Directory**; project-wide ones live at the **Working Directory** root. | Output, workspace file |
| **State File** | `state.json` — the per-**Session** mutable state (current phase, current step, completed step IDs, session state). Lives in the **Session Directory**. Written by the app; read at launch to populate the sidebar after **Session Registry** lookup. | session.json, status file |
| **PRD** | `PRD.md` — the feature specification written by `/to-prd`. Per-feature, which in practice means per-**Session**: canonically lives in the **Session Directory**. Stable; `/ralph` reads but does not mutate. | Spec, design doc |
| **Tasks File** | `tasks.json` — the **Backlog**. Per-session. Lives in the **Session Directory**. Written by `/prd-to-tasks`, mutated by `/ralph` and `/qa`. | Task list file |
| **Progress Log** | `progress.txt` — append-only memory across **Iterations**. Per-session. Lives in the **Session Directory**. Written by `/ralph`. | Journal, log |
| **Events Log** | `events.jsonl` — append-only JSONL of **Execution Events** (step started/completed, subprocess exits, stalls, crashes). Lives in the **Session Directory**. Survives app restart so the user can diagnose a stall. | Event file, log.jsonl |
| **Iteration Logs** | `ralph-logs/iter-N.log` — raw stdout+stderr of each `claude -p /ralph` **Iteration**, one file per iteration. Lives in the **Session Directory**. | Raw logs, subprocess logs |
| **Glossary** | `UBIQUITOUS_LANGUAGE.md` — project-wide domain vocabulary. Lives in the **Metadata Directory** (`.aw/`) because it's a human-edited, committed artifact that spans features. | Dictionary, terms doc |
| **Presence Check** | Startup probe run by `PresenceChecker` that verifies the six **Required Skills** are present in the **Skills Directory** and Claude Code's sandbox is enabled. | Prerequisite check |
| **Presence Banner** | The UI surface rendered by `PresenceBanner` when the **Presence Check** reports missing **Required Skills** or a disabled sandbox. In the skills-packaging design, gains an actionable **Install Missing Skills** button. | Warning banner, missing-skills banner |

## Skill packaging

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Skill Bundle** | The copy of the six **Required Skills** shipped inside the app at `AgentWorkflows/Resources/Skills/{name}/SKILL.md`. The build-time source of truth used by every **Skill Install**, **Skill Update**, and **Skill Removal** action. | Bundled skills, embedded skills |
| **Bundled Skill** | A single **Skill** inside the **Skill Bundle**. Distinct from an **Installed Skill**, which lives in the **Skills Directory**. | Shipped skill |
| **Installed Skill** | A **Skill** present on disk at `{skillsDirectory}/{name}/SKILL.md`. Classified by the **Skill Installer** as **Clean**, **Modified**, or **Stale** based on the **Skill Manifest**. | Deployed skill, user skill |
| **Skill Manifest** | Build-generated file shipped inside the app bundle mapping each **Bundled Skill** file → SHA256. Read-only at runtime; never written. Used to classify **Installed Skills** and to decide what **Skill Update** and **Skill Removal** are allowed to touch. | Hash manifest, shipped-hash manifest |
| **Skill Installer** | The pure-logic module that, given the **Skill Bundle**, the **Skills Directory**, and the **Skill Manifest**, produces a plan of per-skill actions (**Install**, **Update**, **Skip**, **Block**). No UI, no side effects outside a target directory passed in — testable against temp dirs. | Skills manager, installer |
| **Skill Install** | The action of copying a **Bundled Skill** into the **Skills Directory** when no file exists there. First-run path. Never overwrites. Requires user **Install Consent**. | Deploy, copy-in |
| **Skill Update** | The action of overwriting an **Installed Skill** with the matching **Bundled Skill**. Applies cleanly to a **Stale Skill**; requires explicit per-skill confirmation for a **Modified Skill**. Never runs automatically at launch. | Upgrade, refresh |
| **Skill Removal** | The action of deleting an **Installed Skill** directory. Refuses to remove a **Modified Skill**. Symmetric counterpart to **Skill Install**; lives alongside **Skill Update** in the **Skills Preferences Pane**. | Uninstall skill, delete skill |
| **Clean Skill** | An **Installed Skill** whose SHA256 matches the **Skill Manifest** entry for the current app version. Safe to overwrite or remove without prompting. | Pristine, unchanged |
| **Modified Skill** | An **Installed Skill** whose SHA256 does not match any known **Skill Manifest** entry — user has edited it. **Skill Update** requires explicit confirmation; **Skill Removal** is blocked. | Edited skill, user-customized skill |
| **Stale Skill** | An **Installed Skill** whose SHA256 matches an older **Skill Manifest** entry (previously shipped by this app) but not the current one. Eligible for silent **Skill Update** without losing user work. | Out-of-date skill |
| **Missing Skill** | A **Required Skill** with no file at `{skillsDirectory}/{name}/SKILL.md`. Triggers the **Presence Banner**, the **First-Run Skills Modal**, and offers **Skill Install** as the remediation. Not to be confused with **Missing Session**. | Absent skill, uninstalled skill |
| **Install-if-Missing** | The **Skill Installer**'s default policy: act only on **Missing Skills** unless the user explicitly invokes **Skill Update** or **Skill Removal**. The app never silently overwrites an **Installed Skill** at launch. | Non-destructive install |
| **Install Consent** | The user's explicit approval — captured in the **First-Run Skills Modal** or the **Presence Banner** action — authorizing a **Skill Install** to write into the **Skills Directory**. No bundled skill is copied without it. | Permission, opt-in |
| **First-Run Skills Modal** | One-shot welcome sheet shown on cold start when any **Required Skill** is a **Missing Skill**. All-or-nothing: one **Install** action covers all six. Has **Skip** and **Don't Show Again**. | Onboarding sheet, install prompt |
| **Skills Preferences Pane** | Section of the Preferences window listing all six **Required Skills** with per-skill status (**Missing**, **Clean**, **Modified**, **Stale**) and bulk **Skill Update** / **Skill Removal** actions. Host for the modified-vs-clean diff sheet. | Skills settings, skills tab |

## Settings

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Settings** | The effective AW configuration for a **Session**, produced by layering **Per-Repo Settings** over **Global Settings**. Covers CLI choices for title synthesis, Plan, Verify, and Build. Schema and UI deferred to a separate PRD. | Config, preferences |
| **Global Settings** | User-level AW configuration at `~/Library/Application Support/AW/settings.json`. Applies across every **Working Directory**. JSON, app-owned. | User prefs, defaults |
| **Per-Repo Settings** | Repo-level AW configuration at `{workingDirectory}/.aw/settings.json`. Overrides **Global Settings** field-by-field when present. JSON, app-owned, git-tracked. | Project settings, repo config |
| **CLI Preset** | A named option for a **Settings** CLI field. Current values: `.claude` (wired), `.codex` (placeholder — throws `.unavailable`), and `.pi` (planned). The app knows the invocation incantation for each preset; users pick from a dropdown rather than writing raw commands. | Backend, runner choice |
| **Codex** | OpenAI's agentic CLI (`codex exec`). A **CLI Preset** target. Invoked as `codex exec --full-auto -c model_reasoning_effort=<level> --json "$ralph <sessionDirectory>"` for **Iterations**. Emits JSONL one event per line. | — |
| **Pi** | The minimal agentic CLI from the `pi-mono` package. A **CLI Preset** target planned after **Codex**. Tiny core (Read/Write/Edit/bash), session-tree model, OpenAI-compatible endpoint — the primary path for running AW against a local LLM. | pi-mono |
| **Full-Auto Mode** | Codex's `--full-auto` flag, expanding to `-a on-request --sandbox workspace-write`. The invocation mode the codex **Process Runner** uses for unattended **Iterations**. If codex pauses mid-loop waiting for approval, downgrade to `-a never`. | Auto mode |
| **Sandbox Mode** | Codex's `-s` flag: `read-only`, `workspace-write`, or `danger-full-access`. AW runs codex with `workspace-write` (set implicitly via **Full-Auto Mode**) so **Iterations** can edit files inside the **Working Directory** but not elsewhere. | Permission mode |
| **Thread** | Codex's per-invocation session identifier (`thread_id`), emitted on `thread.started`. Analogous to Claude's `session_id`. AW spawns a fresh **Thread** per **Iteration** — the **Ralph Loop** never resumes a prior **Thread**. | Codex session |

## Title synthesis

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Title Synthesizer** | The `SessionTitleSynthesizer` that turns a **Seed** braindump into a short session **Name** via a **Title Synthesis Backend**. Invoked once per **Session** creation. | Namer |
| **Title Synthesis Backend** | The pluggable backend the **Title Synthesizer** calls. Two implementations today: **Foundation Models Title Backend** (default) and **CLI Subprocess Title Backend**. Independent of the **Process Runner** hierarchy — titles are one-shot text, not agent loops. | Title backend |
| **Foundation Models Title Backend** | On-device Apple FoundationModels invocation. The default **Title Synthesis Backend**. No subprocess, no network, no tokens — free and fast. | Apple FM, on-device backend |
| **CLI Subprocess Title Backend** | Alternate **Title Synthesis Backend** that spawns `<binary> -p <prompt>` and reads plain-text stdout. Works for **Claude** and **Pi** (both have a text-mode `-p`). | Shell title backend |
| **Codex Title Backend** | Planned **Title Synthesis Backend** for **Codex**. Unlike **CLI Subprocess Title Backend**, reads the final message from a tempfile passed via `codex exec --output-last-message <file>` — codex's stdout carries a banner, token counts, and the message twice, so stdout is not directly usable. Deferred: titles via codex are an agentic full-turn spawn (3–5s, extra tokens) when **Foundation Models Title Backend** handles the same job for free. | — |

## User actions

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Play** | Toolbar action available only when session state is `.idle`. Starts the **Workflow Engine** from its current position, creating a new **Agent Session** via the **Terminal Engine**. Shows the **Seed** sheet if `plan-grill-me` has not yet completed. | Start, run |
| **Stop** | Toolbar action available when session state is `.running`. Calls `WorkflowEngine.stop()` which terminates the **Agent Session** (`activeEngine.terminate()`) and transitions the session to `.idle`. Destructive to **Agent Session** history. | Pause (colloquial but misleading — see Flagged ambiguities) |
| **Continue** | Toolbar action available when session state is `.paused` or `.stalled`. Resumes the **Workflow Engine** from where it left off, reusing the existing **Agent Session** if one is alive, otherwise spawning a fresh one. The recovery path out of **Stall**. | Resume |
| **Run From Here** | Per-**Step** action (the `play.circle` button in the **Workflow Inspector**). Clears completions from the target **Step** onward, repositions the **Workflow Engine** pointer, and re-dispatches the **Step**'s prompt. Intended to allow targeted re-execution, including mid-run resend. | Rerun, replay |
| **Open in Finder** | Per-**Session** context-menu action. Opens the **Session Directory** in Finder (not the **Working Directory** root), so users can find session-local artifacts without navigating through `.aw-cache/`. | Show in Finder, reveal |
| **Relocate** | Per-**Session** context-menu action available only for a **Missing Session**. Opens a folder picker; on selection, the app rewrites `workingDirectory` in the **Session Registry** entry and re-checks reachability. | Repoint, move |
| **Rename** | Per-**Session** context-menu action. Mutates the **Session**'s `name` in the **Session Registry** only — the **Session Directory**'s UUID name on disk is never changed. | Retitle |

## Engine state

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Session State** | The user-visible lifecycle state of a **Session**: `.idle`, `.running`, `.paused`, `.stalled`, `.completed`. Persisted on `Session.state` inside the **State File**. Drives toolbar affordances. | Status |
| **Execution State** | The **Workflow Engine**'s internal flag (`executionState`: `.idle`/`.executing`/`.paused`/`.completed`). Distinct from **Session State** and sometimes out of sync with it. Gates some operations (e.g. `runFromStep` currently no-ops when `.executing`). | Engine state |
| **Agent Session** | The live `claude` process invoked by the **Terminal Engine** — its PTY, process handle, and the in-memory Claude conversation history it accumulates. Distinct from the app's **Session**. Terminated by **Stop** via `activeEngine.terminate()`, which discards conversation history. | Claude session, terminal session |
| **Missing Session** | Launch-time classification for a **Session Registry** entry whose `workingDirectory` is unreachable (deleted, renamed, moved, unmounted). Rendered dimmed in the sidebar with **Relocate** and **Delete Session** context-menu items; cannot be played or continued until relocated. | Broken session, orphan |

## Cleanup and state

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Session Deletion** | Action that removes a **Session**: delete the **Session Directory** (`{workingDirectory}/.aw-cache/{sessionID}/`) and remove the matching entry from the **Session Registry**. For a **Missing Session**, only the registry entry is removed. | Delete, cleanup |
| **Migration Cleaner** | Launch-time module (`MigrationCleaner`) that purges stale state on app start — dead **Signal Files**, obsolete Application Support layouts. | Janitor |
| **Stall** | Terminal **Loop Driver** state reached via **Stall Detection** or **Max Iterations** exhaustion without **Convergence**. Maps to session state `.stalled`; Continue re-enters the **Loop** with a fresh iteration budget. | Dead loop, stuck |

## UI surfaces

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Home View** | The landing screen shown when no **Session** is selected (`.home` nav item active). Contains the **Quickstart CTA** and, when **Sessions** exist, the **Recent Sessions** grid. | Dashboard, welcome screen |
| **Quickstart CTA** | The persistent "New Session" button always visible on the **Home View**. The single canonical entry point for **Session** creation. | Create button, new session button |
| **Recent Sessions** | A grid section on the **Home View** showing the last 5–8 **Sessions** with name, **Working Directory**, last-run timestamp, and status badge. | Session list, history |
| **New Session Sheet** | The sheet (`NewSessionView`) for creating a **Session**. Contains the **Path Control** and a name field. Opened by the **Quickstart CTA** or ⌘T. | New session dialog, create dialog |
| **Path Control** | The styled directory picker inside the **New Session Sheet** — a rounded row with a folder icon, the selected path, and a trailing "Choose…" element. The entire row is clickable. Replaces the raw text-field + Browse-button pattern. | Folder picker, directory picker |
| **Session Seed Sheet** | The sheet (`SessionSeedSheet`) shown before the first **Play** of a **Session** to capture the **Seed**. Presented once per **Session**; not shown again after `plan-grill-me` completes. | Grill-me modal, intent modal, start sheet |
| **Session Tab** | One of five named content sections inside a **Session**'s detail view: Terminal, Iterations, Files, Diff, Log. Switched with ⌘1–⌘5. | Panel, pane, view |
| **File Viewer** | The Files **Session Tab** (`DocsView`). Displays session-related files (MD, JSON, XML, plaintext) with syntax coloring and a word-wrap toggle. | Docs view, file browser |
| **Iterations Display** | The Iterations **Session Tab** (`IterationsView`). Shows one **Iteration Card** per **Iteration**. | Iterations panel, iterations tab |
| **Iteration Card** | A single card in the **Iterations Display** representing one **Iteration**, including its tool calls and events in a collapsible JSON tree. | Iteration row, iteration item |
| **Log View** | The Log **Session Tab** (`ExecutionLogTabView`). Renders **Execution Events** from the **Events Log** with color coding by event type. Distinct from the **Events Log** file it reads. | Log tab, log panel, execution log |
| **Inspector Panel** | The right sidebar (`WorkflowInspector`) toggled by a toolbar button. Lists **Phases** and **Steps** with completion state and per-**Step** **Run From Here** actions. Hosts the **Continue Gate** when a **Pause Step** is reached. | Right panel, inspector sidebar |
| **Continue Gate** | The approval button inside the **Inspector Panel** — shown when a **Pause Step** halts the **Workflow Engine**. Styled as a centered, blue, rounded primary button. Clicking it is the in-UI equivalent of writing a **Signal File** manually. | Yes button, approve button, continue button (ambiguous — see Flagged ambiguities) |

## Relationships

- A **Session** has exactly one **Session Directory** and one **Working Directory**. The **Session Directory** lives inside the **Working Directory**.
- Every **Session** has exactly one entry in the **Session Registry**; the entry is authoritative for `{id, name, workingDirectory, workflowName}` and nothing else.
- **Session Directory** and **Progress Directory** are the same path. The two names exist because different layers reach it for different reasons: the app sees it as storage; `/ralph` sees it as the `$1` argument.
- A **Workflow** contains **Phases**; a **Phase** contains **Steps**; an **Iterate-Tasks Step** contains nested **Steps** driven by the **Loop Driver**.
- The **Workflow Engine** owns the outer **Phase**/**Step** tree; the **Loop Driver** owns **Iterations** inside an **Iterate-Tasks Step**.
- Every CLI **Step** injects through a **Terminal Engine**; every injection carries a **Signal Footer**; every completion waits on a **Signal File**.
- The **Ralph Loop**'s **Backlog** is a sequence of **Tasks**; **Iterations** continue until every **Task** has `passes: true` (**Convergence**), the **Loop Driver** detects a **Stall**, or **Max Iterations** is reached.
- The **Home View** always shows the **Quickstart CTA**; when any **Sessions** exist it also shows the **Recent Sessions** grid.
- The **Inspector Panel** shows the **Continue Gate** only when the current **Session State** is `.paused` (a **Pause Step** is active). At all other times it shows the phase/step list with **Run From Here** affordances.
- The **Log View** reads from the **Events Log** file — they are not the same thing. The **Events Log** is a file artifact; the **Log View** is the UI surface that renders it.
- The **Session Seed Sheet** captures the **Seed**; it is shown once per **Session** and only when no **Seed** has been captured yet.
- The **Path Control** lives exclusively inside the **New Session Sheet**. The **Relocate** action (for **Missing Sessions**) reuses the same `NSOpenPanel` but is not the **Path Control** — it has no persistent display row.
- Per-session **Coordination Artifacts** (**State File**, **Tasks File**, **Progress Log**, **Events Log**, **Iteration Logs**, **PRD**) live under the **Session Directory** (inside the **Cache Directory**); project-wide artifacts (**Glossary**, **Per-Repo Settings**) live in the **Metadata Directory**.
- **Metadata Directory** and **Cache Directory** are siblings under the **Working Directory**. The former is committed, the latter is gitignored. No file moves between them.
- **Settings** compose by layering: the app reads **Global Settings**, then overrides each present field from **Per-Repo Settings**. Either file may be absent.
- A **Session** owns at most one live **Agent Session** at a time. **Play** creates one; **Stop** destroys one (losing Claude conversation history); **Continue** reuses the existing one if present.
- **Session State** is user-facing and drives the toolbar; **Execution State** is internal to the **Workflow Engine**. Divergence between them is the source of several bugs identified in this conversation.
- The **Skill Bundle** ships inside the app and contains exactly the set enumerated by **Required Skills**. A unit test asserts the two sets are equal; drift is a build failure.
- A **Required Skill** is in exactly one of four states per launch: **Missing Skill**, **Clean Skill**, **Modified Skill**, or **Stale Skill**. The **Skill Manifest** is the oracle.
- **Skill Install** is gated by **Install Consent** collected from the **First-Run Skills Modal** or the **Presence Banner**. **Skill Update** and **Skill Removal** are always user-initiated from the **Skills Preferences Pane** — never automatic.
- **Skill Removal** refuses to touch a **Modified Skill**; **Skill Update** on a **Modified Skill** requires extra per-skill confirmation. **Clean Skills** and **Stale Skills** are acted on freely.
- Every **Iteration** carries exactly one **Effort Level**, resolved from the current **Task**'s `effort` field before the subprocess spawns. The **Loop Driver** reads the field; the **Process Runner** translates it to an `--effort` argv pair.
- **Effort** is a **Process Runner** protocol parameter, not a **CLI Preset**-specific concept. A future Codex **Process Runner** accepts the same **Effort Level** and maps it to Codex's equivalent reasoning flag.
- The **Iteration Logs** record the **Effort Level** chosen for each iteration (`[effort] medium`) alongside the existing `[stderr]` and `[exit]` lines — the only user-visible surfacing of **Effort**.
- A **Process Runner** owns exactly one **Event Stream Decoder**. The decoder translates CLI-native JSONL into **Iteration Events**. Claude's runner + `StreamJsonDecoder` is the only wired pair today; Codex and Pi will each add their own pair. No shared decoder protocol exists — deferred until three examples are observable.
- A **Skill Bundle** can be written to multiple **Skill Targets**. One **Required Skill** therefore produces N copies on disk — one per enabled target — all byte-identical. The **Skill Manifest** classifies each copy independently (**Clean** / **Modified** / **Stale** / **Missing**).
- **Skill Invocation** syntax is CLI-specific (`/name` for Claude, `$name` for Codex); the **Skill** file on disk is not. The same `SKILL.md` bytes drive both.
- Every **Iteration** maps an **Effort Level** to a CLI-specific reasoning flag inside the **Process Runner**: Claude uses `--effort <level>`, Codex uses `-c model_reasoning_effort=<level>`. The **Effort** enum's `rawValue` is the shared vocabulary — no translation table needed.
- The **Title Synthesizer** is independent of the **Process Runner** hierarchy. **Foundation Models Title Backend** is the default — chosen because titles are cheap and bounded, ideal for on-device inference. **CLI Subprocess Title Backend** is opt-in per **CLI Preset** (**Title Preset**), and Codex is explicitly excluded from it.

## Example dialogue

> **Dev:** "Why do we have both `.aw/` and `.aw-cache/`? Feels redundant."
>
> **Domain expert:** "They have opposite lifecycles. The **Metadata Directory** is committed — it holds the **Glossary**, the **PRD**, and eventually **Per-Repo Settings**. Humans edit those and want them in git. The **Cache Directory** is gitignored — every **Session Directory** lives inside it, holding per-session ephemera like the **State File** and **Iteration Logs**. Mixing committed and ignored files in one directory with whitelist gitignores is a papercut; two dirs is honest."
>
> **Dev:** "Where does the **Tasks File** live now that the **Session Symlink** is gone?"
>
> **Domain expert:** "Inside the **Session Directory** at `{workingDirectory}/.aw-cache/{sessionID}/tasks.json`. The `$1` argument `/ralph` receives is that same absolute path, and the subprocess's cwd is the **Working Directory**, so the path resolves inside cwd and Claude Code doesn't block the read."
>
> **Dev:** "If the user deletes the repo, what does the sidebar look like next launch?"
>
> **Domain expert:** "The **Session Registry** still has the entry. At launch the app stats `workingDirectory` for each entry — that one fails, so the **Session** is flagged as a **Missing Session**. The sidebar renders it dimmed with **Relocate** and **Delete Session** available. Play and Continue are disabled until **Relocate** points the entry at a real folder containing `.aw-cache/{sessionID}/`."
>
> **Dev:** "And if the user wants `codex` for Verify but `claude` for the Ralph loop?"
>
> **Domain expert:** "That's what **Settings** will be for. Each CLI field is an independent **CLI Preset** dropdown. **Global Settings** sets the user's default; **Per-Repo Settings** in the **Metadata Directory** overrides per-project. The app owns both files — JSON, no hand-editing required."
>
> **Dev:** "How does a **Task**'s `effort` field reach `claude -p`?"
>
> **Domain expert:** "The **Loop Driver** reads the current **Task** from the **Tasks File** before every **Iteration** — same first-unpassed-wins rule `/ralph` itself uses, so the two agree on which task is active. It resolves the `effort` string into an **Effort Level**, clamping anything above `high` and defaulting to `medium` on missing or unknown values, then passes the **Effort Level** into the **Process Runner**. The **Process Runner** appends `--effort <level>` to the subprocess argv and writes `[effort] <level>` to that iteration's **Iteration Log**."
>
> **Dev:** "And when the user switches their Build **CLI Preset** to **Codex**, what changes?"
>
> **Domain expert:** "`ProcessRunnerFactory.make(.codex)` returns a `CodexProcessRunner` instead of `ClaudeProcessRunner`. The argv shape changes — `codex exec --full-auto -c model_reasoning_effort=<level> --json \"$ralph <sessionDirectory>\"` — and the runner pipes stdout through its own **Event Stream Decoder** that translates codex's JSONL into **Iteration Events**. The **Loop Driver** upstream doesn't notice: it sees the same `sessionStarted` / `assistantText` / `toolUse` / `toolResult` / `iterationFinished` stream regardless of which CLI produced it. **Effort** is passed in the same way — same `rawValue`, different flag."
>
> **Dev:** "So the `/ralph` **Skill** has to exist for Codex too?"
>
> **Domain expert:** "Yes, at `~/.codex/skills/ralph/SKILL.md` — same bytes, same frontmatter as the Claude copy. The **Skill Installer** handles it by enabling `.codex` as an additional **Skill Target**; the one **Skill Bundle** gets written to both **Skills Directory** and **Codex Skills Directory**. The **Skill Invocation** syntax inside the codex prompt is `$ralph` — codex resolves it against its own skills directory. Codex will silently refuse a `SKILL.md` that's missing YAML frontmatter, so drift from the Claude format is a functional break, not a cosmetic one."
>
> **Dev:** "Could we do titles with Codex?"
>
> **Domain expert:** "Technically feasible, but deliberately deferred. The default **Title Synthesis Backend** is **Foundation Models Title Backend** — on-device, free, instant. The opt-in shell alternative is **CLI Subprocess Title Backend**, which reads `<binary> -p <prompt>` stdout directly; that works for Claude and **Pi** because both return clean plain text. Codex's `exec` stdout carries a banner and token counts around the answer, so the direct-stdout path can't be reused. Codex does offer `--output-last-message <file>` which writes the final message cleanly — a **Codex Title Backend** would use that. We're not wiring it up now because firing a full agent turn for a 5-word title costs 3–5s and extra tokens versus Foundation Models doing it for free. Scope call, not a feasibility wall."

## Flagged ambiguities

- **"Task"** was used for both a **Step** (unit of **Workflow** execution) and a **Task** (entry in the **Backlog**). Canonical: **Step** for workflow-level units, **Task** for backlog items. `tasks.json` holds **Tasks**; `Workflow.ralph.phases[].steps[]` holds **Steps**.
- **"Iteration"** was sometimes used for any loop cycle. Canonical: one **Iteration** is exactly one pass through the **Iterate-Tasks Step**'s nested children, i.e. one `/ralph` invocation. A full **Ralph Loop** run may contain many **Iterations**.
- **"Session Directory" vs "Progress Directory"** are now the same path and are used interchangeably. The old design had a separate Application Support location bridged by a **Session Symlink**; that bridge has been removed. If either term is used in isolation, it refers to `{workingDirectory}/.aw-cache/{sessionID}/`.
- **"Session Symlink"** was a term in earlier revisions for the bridge between **Working Directory** and an Application Support-hosted session folder. **Retired.** There is no symlink in the current design — the **Session Directory** is a plain directory inside the **Working Directory**, and the **Session Registry** is the only thing in Application Support.
- **"Cleanup"** was used for both the deletion sweep (dead code, legacy files) and the **Session Deletion** flow. Canonical: **Cleanup** for the one-time deletion PR; **Session Deletion** for the ongoing app behavior when the user deletes a **Session**.
- **"Signal"** was ambiguous between the Unix signal and the **Signal File** completion mechanism. Canonical: **Signal File** always, and the `{signal-path}` template variable resolves to it.
- **"Pause"** is used colloquially for what the UI and code actually call **Stop**. There is no true pause affordance — the `.paused` **Session State** exists, but the toolbar control that reaches it destroys the **Agent Session**. Canonical: call the toolbar button **Stop** and acknowledge that any flow requiring "pause then resume" today is really "destroy **Agent Session** then start a new one, losing history."
- **"Session"** was ambiguous between the app's **Session** (persistent, has a **Session Directory** and **Workflow** position) and the **Agent Session** (the live `claude` conversation). Canonical: **Session** for the app concept, **Agent Session** for the `claude` process's PTY + conversation. One app **Session** can be associated with zero, one, or (across its lifetime) many successive **Agent Sessions**.
- **"Play"** was overloaded: the toolbar **Play** (start a stopped session) and the per-**Step** `play.circle` **Run From Here** button. Canonical: **Play** for the toolbar; **Run From Here** for the per-**Step** action. These have distinct semantics: **Play** resumes the engine from its current pointer; **Run From Here** repositions the pointer first.
- **".aw/" vs ".aw-cache/"** sound similar and invite confusion. Canonical: **Metadata Directory** (`.aw/`) for committed human-edited artifacts; **Cache Directory** (`.aw-cache/`) for gitignored ephemera including every **Session Directory**. Rule of thumb — if the engine writes it and can regenerate it, it belongs in the **Cache Directory**; if a human deliberately edits it and wants it in git, it belongs in the **Metadata Directory**.
- **"Missing"** — the glossary has two distinct **Missing** concepts. A **Missing Session** is a **Session Registry** entry whose **Working Directory** is unreachable. A **Missing Skill** is a **Required Skill** absent from the **Skills Directory**. They share only the word; remedies and blast radius are unrelated (**Relocate** vs **Skill Install**).
- **"Install"** — historically conflated with "copy a zip into `~/.claude/skills/` by hand." Canonical: **Skill Install** is a specific, consented **Skill Installer** action that copies exactly one **Bundled Skill** into the **Skills Directory** and never overwrites. Manual user file-copies are out of the model.
- **"Skill" source of truth** — the **Bundled Skill** is the app's shipped copy; the **Installed Skill** is what Claude Code actually reads. They can diverge (a **Modified Skill** or a **Stale Skill**). The **Skill Manifest** is the bridge that lets the **Skill Installer** tell the two apart safely.
- **"PRD" scope** — the **PRD** is per-feature and canonically lives in the **Session Directory** (one PRD per **Session**). During alpha, out-of-tree **PRD**s sometimes sit at the repo root as temporary scratch for planning work that spans or predates a real **Session** (e.g. a PRD authored before the session that will execute it exists). Repo-root PRDs are expedient-only; the canonical home is the **Session Directory**.
- **"Effort"** is overloaded in general software usage (t-shirt sizing, story points, human estimation). Canonical AW usage: **Effort** is the reasoning-budget knob passed to `claude -p --effort`, sourced per-**Task** and applied per-**Iteration**. Nothing to do with human estimation. A **Task** authored with `effort: "high"` does not mean "this is a lot of work" — it means "let the model spend more reasoning tokens on it."
- **"Process Runner" vs "Terminal Engine"** — both spawn `claude`, but they serve different layers. The **Terminal Engine** owns the interactive PTY for non-loop **Steps** and long-lived prompt injection; the **Process Runner** is headless, one-shot per **Iteration**, and lives behind the **Loop Driver**. A running **Session** typically has one **Terminal Engine** and, during a Build phase, many sequential **Process Runner** invocations.
- **"Log"** — ambiguous between the **Log View** (the UI tab) and the **Events Log** (the `.jsonl` file in the **Session Directory**). Canonical: **Log View** for the UI surface, **Events Log** for the file. "Opening the log" means opening the **Log View**; "parsing the log" means reading the **Events Log**.
- **"Continue"** — used for two distinct things: the **Continue** toolbar action (resumes the **Workflow Engine** from `.paused` or `.stalled`) and the **Continue Gate** (the approval button inside the **Inspector Panel** for a **Pause Step**). Canonical: **Continue** for the toolbar action; **Continue Gate** for the inspector button. They often fire together but are separate affordances.
- **"Inspector"** — could refer informally to any right-side panel or the SwiftUI `.inspector` modifier. Canonical: **Inspector Panel** always, for the specific right sidebar defined by `WorkflowInspector`.
- **"Skill"** was used for both the file on disk and the in-prompt invocation. Canonical: **Skill** for the `SKILL.md` file + its frontmatter (the *thing* copied by the **Skill Installer**); **Skill Invocation** for the in-prompt prefix syntax (`/name` or `$name`) that triggers it. A broken **Skill Invocation** can fail even when the **Skill** is present (e.g., codex rejecting a SKILL.md with missing frontmatter).
- **"Session"** is three-way ambiguous now that Codex is on deck: the app **Session** (persistent, has **Session Directory**), the **Agent Session** (live `claude` PTY + conversation), and Codex's **Thread** (per-invocation id). Canonical: name the layer — **Session** for the app concept, **Agent Session** for Claude's PTY, **Thread** for Codex's per-invocation id. One **Iteration** produces exactly one **Thread** when running under codex.
- **"Decoder"** — **Event Stream Decoder** is the abstraction-in-waiting. `StreamJsonDecoder` is the concrete Claude-specific one. Do not refer to `StreamJsonDecoder` as "the decoder" in cross-CLI contexts — that term is generic. Use **Event Stream Decoder** for the concept, specific class names for the instances.
- **"Runner"** — ambient word that could mean **Process Runner**, **Loop Driver**, **Subprocess Runner**, **Workflow Engine**, or **Terminal Engine**. Always qualify. "The runner" without qualification is a code-review smell.
- **"Title backend"** — loose usage sometimes lumps **Foundation Models Title Backend** and **CLI Subprocess Title Backend** with **Process Runner** implementations. Canonical: **Title Synthesis Backend** is its own hierarchy, one-shot, text in / text out. **Process Runners** drive agent loops. They share no protocol and shouldn't.
- **"`$` vs `/`"** — both are **Skill Invocation** syntaxes, but they behave identically under `codex exec` (both resolve against `~/.codex/skills/<name>/SKILL.md`). `$` is the codex-primary form per OpenAI's docs; `/` has known flakiness in the interactive codex TUI. Canonical: use `$` when invoking under codex; use `/` under Claude.
