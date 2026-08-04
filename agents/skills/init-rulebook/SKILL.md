---
name: init-rulebook
description: "Load and rehydrate the user-level agent rulebook by reading `~/.agents/AGENTS.md` plus every top-level `~/.agents/rules/*.md` file. Use when handling explicit requests such as init rulebook, reload rulebook, or load user-level agent rules, or when rehydrating after context compaction."
user-invocable: true
alwaysAllow: ["Read", "Glob", "Grep"]
---

# Init user's agent rulebook

Load the **user's agent rulebook** — the global rule set under `~/.agents/` (`AGENTS.md` plus every top-level Markdown file in `rules/`) — into working context. Run this skill on every invocation; do not assume the rulebook from a prior turn is still present.

## Rehydrate after compaction

Context compaction drops or distills earlier file reads. After compaction (or when rulebook content looks summarized or missing):

1. **Treat prior rulebook knowledge as stale.** Do not rely on remembered rule text from before compaction.
2. **Re-run this skill immediately** — read the index and every discovered rule file again in this turn, before continuing the user's task.
3. **Silent rehydration.** Do not summarize, echo, or confirm the rulebook to the user unless they asked about it.
4. **Then resume work** with the freshly loaded user's agent rulebook applied.

If the user says **rehydrate**, **reload rulebook**, **init rulebook**, **load user's agent rulebook**, or **load user-level agent rules**, execute the steps below even when you believe the rulebook was loaded earlier in the session.

## Steps (every invocation)

1. **Read the index completely:** `~/.agents/AGENTS.md` (or where it is aliased or symlinked from).
2. **Discover rules from disk:** enumerate every top-level `*.md` file in `~/.agents/rules/`. Do not recurse, and do not derive membership from index references or an embedded filename list.
3. **Sort deterministically:** order the discovered files by basename in ascending lexical order; numeric prefixes establish the intended sequence.
4. **Read every discovered rule completely:** treat any unreadable file or failed read as an error and report the exact path. Do not silently skip it.
5. **Confirm completion:** record the discovered count and successfully read count. Loading is complete only when the counts are equal.
6. **Absorb silently:** do not summarize, echo, or confirm the rulebook to the user.
7. **Apply rulebook-side semantics:** loading a rule is distinct from applying it. Honor applicability declared by the rule files and rulebook index for the remainder of the session, until the next compaction or explicit re-invocation.

## Behavior

- **User's agent rulebook = index + exhaustive top-level rule discovery, every time.** Never skip `AGENTS.md` or a discovered rule file.
- **No deferral.** Read the complete discovered set in one pass, including rules whose activation conditions do not match the current task.
- **Silent operation.** No user-visible output unless explicitly asked about the rulebook.
- **Compaction = reload.** Any turn after compaction should treat loading the user's agent rulebook as required, not optional.
