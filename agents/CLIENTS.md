# Agent client projections

`AGENTS.md` and the top-level `rules/*.md` files are the canonical rulebook. Through `init-rulebook`, the index loads always-on rules eagerly, task-conditional rules for matching work, and action-gated rules immediately before matching operations; client projections are delivery mechanisms only and do not own membership or applicability.

| Client | Ownership | Bootstrap / refresh | Verification |
|---|---|---|---|
| Generic `~/.agents` consumers | Manifest-managed | `make link` installs the whole `agents/` directory at `~/.agents` | `bash scripts/link.sh --check` |
| Claude Code | Manifest-managed compatibility links | `make link` installs `~/.claude/CLAUDE.md`, `skills`, `agents`, and `commands` from the canonical tree | `bash scripts/link.sh --check` |
| Codex | Manifest-managed bootstrap bridge | `make link` installs `config/codex/AGENTS.md` at `~/.codex/AGENTS.md`; the bridge invokes `init-rulebook` and retains optional local `RTK.md` guidance | `bash scripts/link.sh --check`; confirm a new task loads the canonical rulebook |
| Zed Agent (native) | Manifest-managed bootstrap bridge | `make link` installs `config/zed/AGENTS.md` at `~/.config/zed/AGENTS.md`; the bridge invokes `init-rulebook` at session start and after compaction and applies optional RTK guidance to terminal commands | `bash scripts/link.sh --check`; confirm a new native Zed Agent thread loads the canonical rulebook |
| Zed External Agents (ACP) | Agent-owned native configuration | Zed hosts the thread, but each external agent owns its instruction loader; Codex continues to use the Codex bridge and native config rather than Zed's personal `AGENTS.md` | Confirm the selected external agent loads its own native instructions |
| OpenCode | Manifest-managed user bridge and native skill discovery | `make link` installs `config/opencode/AGENTS.md` and `config/opencode/opencode.jsonc` under `~/.config/opencode/`. OpenCode discovers `~/.agents/skills` automatically. The bridge invokes `init-rulebook` at startup and after context compaction. | `make agent-clients-check`; inspect the skill catalog after discovery completes, then confirm rulebook loading in a fresh session outside this repo |
| Cursor skills | Manifest-managed compatibility link | `make link` installs `~/.cursor/skills` from the canonical skills tree | `bash scripts/link.sh --check` |
| Cursor rules | Manifest-managed file plus account startup pointer | `make link` installs `config/cursor/rulebook.mdc` at `~/.cursor/rules/rulebook.mdc`. In Customize → Rules, set the startup User Rule to `config/cursor/user-rule.txt`; account rules are vendor-synced, not restored by the linker. | `make agent-clients-check`; inspect the account pointer and a fresh session outside this repo |
| VS Code Copilot | Manifest-managed user bridge | `make link` installs `config/copilot/copilot-instructions.md` at `~/.copilot/copilot-instructions.md`, the personal always-on entrypoint for the Copilot harness. Other harnesses retain their own instruction discovery. | `make agent-clients-check`; Agent Customizations → Instructions and a fresh Copilot session |
| Antigravity | Manifest-managed user bridge | `make link` installs `config/antigravity/GEMINI.md` at `~/.gemini/GEMINI.md`. Read the loader skill directly if skill invocation is unavailable. | `make agent-clients-check`; fresh session when Antigravity is installed |
| Nimbalyst | Host-managed | No stable repository-owned projection path is declared; the host may consume `~/.agents` | Confirm the active task exposes the current rulebook before relying on Nimbalyst-specific rules |

The macOS manifest owns bridge placement, not runtime acceptance. Cursor's account
User Rule is a separate vendor setting; use the tracked startup text and preserve
unrelated account rules. Do not link the entire canonical rules directory into an
always-on rules folder. Windows consumer paths are unchanged.

`make agent-clients-check` verifies managed symlinks and matching contents for
Codex, Claude Code, Zed, OpenCode, Cursor, Copilot and Antigravity. Claude Code retains the
public canonical-index link. Skills and MCP connectivity do not prove instruction
loading. Antigravity's `~/.gemini/GEMINI.md` can also affect other Gemini clients.

Verify each installed client with a fresh session outside this repository: inspect
the startup source, index and always-on reads, one matching conditional rule,
deferred action gates, and rehydration after compaction. Account settings, remote
profiles, harness differences and fresh-machine behavior require separate checks.
This public projection has fixture coverage, not a live-client acceptance claim.

### Rulebook changes (2026-10-19)

- Five rules are always on: core, authorization, worktree hygiene, skill owners
  (`12-skill-owners.md`) and anti-patterns. Skill owners lists discovery defaults
  so routing does not depend on skill descriptions a client may truncate.
- Design posture is conditional on interface, UX, or visual-artifact work. Skill
  routing loads for selections starting from rule 12, overlapping choices, named
  skill requests, or cross-skill references.
- Claude Code keeps its direct `~/.claude/CLAUDE.md` link to the canonical index,
  so it follows the index's loading procedure like the bridged clients.
- Skill discovery stays shared across clients; no per-client skill curation or
  invocation overrides are applied. Nested skill directories remain supported by
  Cursor discovery. No live startup or forced compaction acceptance is claimed.

## Mac RTK hooks

Mac bootstrap and `make all` merge the automatic RTK hooks through
`make restore-codex-rtk` and `make restore-claude-rtk`. Check them with
`make codex-rtk-check` and `make claude-rtk-check`. Reload the client and review
and trust its exact hook locally. Windows retains instruction-based RTK guidance.

### Claude Code startup checkpoint

On Mac, `make restore-claude-rulebook` merges the repository-owned hook adapter
into local Claude settings; `make claude-rulebook-check` checks its definitions.
Claude Code 2.1.295+ is required for `onFailure: block` when the gate cannot start
or times out. Other settings, permissions and the RTK hook are retained. Setup
and verification defer when Claude Code is absent; bootstrap records the stage
as deferred. Run the restore target after installing it. Version probes time out.
The public Claude canonical-index link stays unchanged; no native imports are added.

SessionStart validates the index/inventory using metadata for deferred rules.
InstructionsLoaded records actual native delivery of the index and always-on
rules; successful Read results count only when their complete returned content
matches the file. Successful loading of `init-rulebook` alone does not open the
gate. After choosing applicable rules and necessary references from the index,
the agent runs the printed `claude-rulebook.py ... complete --rules ...` command.
It verifies all selected read evidence before sealing the checkpoint. No keyword
classifier or second routing table chooses those files. Semantic selection is
still model judgment; a deliberately incomplete selection cannot be inferred
from file-read evidence alone.

Before sealing, only canonical bootstrap Read/Glob, `init-rulebook`, and the
literal checkpoint control command are admitted. Project reads, shell commands,
other skills and connector tools remain blocked. Action-gated rules are excluded
from startup; once ready, their existing just-in-time policy applies. Missing
inventory, partial/failed/stale reads and corrupt session state keep the gate
closed. An inventory error permits only Read/Edit/Write of the canonical index
for repair; prompts remain usable. A missed SessionStart recovers on the next
main-session event, requiring fresh explicit reads. Hook errors/timeouts block
project tools. Stop requests completion once; if the continuation still cannot
complete, it stops with a repair diagnostic while project tools remain closed.

Each human prompt requires a fresh selection/checkpoint, reusing complete reads
already delivered in the current context. System peer/task reports preserve the
current checkpoint, identified by host transcript provenance and prompt ID;
when the transcript is appended after submission, resolution waits until the
next main-agent tool or Stop. Missing provenance requires fresh selection.
Child events identified by `agent_id` bypass this main-session adapter without
reading or changing parent proof; its completion command is denied to children.
This isolates accidental parent-state changes, not an agent deliberately
rewriting local state. Read callbacks are bound to their prompt/context, so delayed old callbacks cannot repopulate a reset. SessionStart
on resume/clear/compaction invalidates prior read evidence and requires explicit
Read of the index/always-on files: asynchronous native-import events cannot be
reliably assigned to the new context. Native imports count without duplicate
reads at first startup. State under `~/.claude/state/rulebook/` is per-session and lock-protected;
it stores paths/hashes and prompt IDs, not prompts or tool contents. A fresh session repairs
stale state; malformed inventory can be corrected through the index repair path. Hook setup
errors are checked with the restore/check targets rather than bypassed.

`tests/test_claude_rulebook.py` covers the actual hook boundary and the trace
grader. `scripts/check-rulebook-startup.py` checks successful complete reads and
a successful checkpoint **before** task tools, and separately checks required
and forbidden files. It requires completed read deliveries before the checkpoint
request and a bound successful receipt; stream-json may emit the next tool request
before logging the previous command result. Earlier valid reads survive later
rereads; batched Read results count only when their numbered text matches the
whole file. Receipts bind the control command's Python independently of the
interpreter running the checker. The runtime gate checks sealed state
before that tool executes. Restricted harnesses must offer Bash for the literal
checkpoint command. Eventual invocation alone cannot pass. This public adapter
has fixture coverage, not a live-client acceptance claim.
It targets main Claude Code sessions on Mac; it adds no Codex/Windows hook or
subagent runtime claim.
