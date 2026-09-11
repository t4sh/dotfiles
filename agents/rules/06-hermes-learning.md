# 06 — Hermes learning

Activate when Hermes captures learning or performs skill maintenance.
Shared skill authoring also follows `11-skill-routing.md`.

## Learning destinations (Hermes)

Capture repeated or high-value verified lessons proactively within the authorized
task. Classify each lesson before writing it:

| Learning | Destination | Capture rule |
| --- | --- | --- |
| Reusable method, troubleshooting procedure, or verified workflow | `~/.agents/skills/<skill-name>/SKILL.md` | Search the shared and Hermes-local skill indexes first; improve the appropriate existing skill before creating another. New personal skills belong in the shared collection. |
| Project architecture, decisions, environment, or unfinished work | That project's existing documentation or `.agent-memory/` | Follow the project's memory convention and index. Keep project identity explicit; if `.agent-memory/` is absent, use existing project docs rather than creating a memory system. |
| Stable personal preference about working with the user | Hermes user memory (`memory` tool, `user` target) | Store a concise preference consistent with the rulebook; keep project-specific facts out of the user profile. |
| Proposed change to governing rules, permissions, or skill-routing policy | A proposed edit to `~/.agents/rules/` for user review | Apply only when the user explicitly authorizes the rule change. Observed behavior and memory entries do not amend governing rules. |
| Unverified hypothesis or temporary task state | Current session or the project's existing task notes | Validate before promoting to reusable guidance; discard transient detail when it stops being useful. |

`~/.agents` is the canonical user-level entry point, linked to the dotfiles
checkout. Hermes's `skills.create_dir` must resolve to `~/.agents/skills`; verify
the active profile's destination before creating a skill. Report a mismatch
rather than silently creating a second collection. Existing skills are edited
at their owning source; moving a Hermes-local or vendor-managed skill into the
personal collection requires checking ownership and collisions first.

Distill the procedure and the evidence that makes it trustworthy. Session logs,
client-specific data, credentials, and one-off project paths stay out of shared
skills. Separate a portable procedure from any project details needed to execute
it. A useful correction is enough reason to improve an existing skill; a completed
task alone is not enough reason to create one.

Keep learning changes small and summarize the destination and verification in
the task handoff. Follow the existing authorization rules for commits, pushes,
destructive changes, and publication; automated learning does not authorize them.

## Cross-project consistency

- **Confirm context:** before persisting project learning, resolve the active
  session's project directory and Hermes profile. Do not infer the project from
  a previous session or the gateway's launch directory. If ownership is ambiguous,
  keep the lesson in the session and clarify before writing project or shared files.
- **Classify before promotion:** keep project-specific conventions in that project's
  existing docs, memory, or skill collection. Follow its established storage and
  trust conventions; do not introduce a per-project Hermes setup just to save a
  lesson. Promote only a verified reusable procedure into `~/.agents/skills`, with
  project-specific assumptions removed or exposed as explicit inputs.
- **Resolve collisions:** before creating or updating a skill, inspect matching
  names and overlapping purposes across project, profile-local, and shared skills.
  Identify the effective source for this session and the exact file to be edited.
  Verify resolution against the installed runtime; a listing label or skill name
  alone does not establish provenance. Resolve ambiguous ownership before writing.
- **Preserve shared defaults:** keep a project exception local, or express it as
  an explicit condition in the shared procedure when it generalizes. Do not silently
  replace shared defaults with one project's requirements. Avoid duplicate shared
  skills created solely to bypass a local override.
- **Check shared impact:** when changing shared behavior, check the originating
  use case and one contrasting project scenario. Use safe fixtures or scenario
  review without modifying an unrelated project. Distinguish executed checks from
  reasoning-only review and untested cases; record remaining scope limitations.

Consistency means explicit ownership, predictable resolution, and deliberate
promotion. Legitimate project differences remain local; shared changes must not
silently change another project's conventions.
