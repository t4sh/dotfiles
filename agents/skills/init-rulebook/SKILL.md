---
name: init-rulebook
description: "Load and rehydrate the user-level agent rulebook from `~/.agents/AGENTS.md`: eagerly read always-on rules, select task-conditional rules, and defer action-gated rules until the matching operation. Use when starting a session, recovering after context compaction, or handling explicit requests such as init rulebook, reload rulebook, or load user-level agent rules."
user-invocable: true
alwaysAllow: ["Read", "Glob", "Grep"]
---

# Init user's agent rulebook

Load the **applicable portion of the user's agent rulebook** under `~/.agents/`: the complete `AGENTS.md` index, every rule classified there as always-on, and each task-conditional rule whose section trigger matches the current task or environment. Retain action-gated headings from the index, but do not load their rules until immediately before a matching operation. Run this skill on every invocation; do not assume the rulebook from a prior turn is still present.

## Rehydrate after compaction

Context compaction drops or distills earlier file reads. After compaction (or when rulebook content looks summarized or missing):

1. **Treat prior rulebook knowledge as stale.** Do not rely on remembered rule text from before compaction.
2. **Re-run this skill immediately** — read the index, validate the complete inventory, and reload every always-on and task-conditional rule applicable to the current task before continuing. Reload an action-gated rule only when the resumed operation is already at that gate.
3. **Silent rehydration.** Do not summarize, echo, or confirm the rulebook to the user unless they asked about it.
4. **Then resume work** with the freshly loaded user's agent rulebook applied.

If the user says **rehydrate**, **reload rulebook**, **init rulebook**, **load user's agent rulebook**, or **load user-level agent rules**, execute the steps below even when you believe the rulebook was loaded earlier in the session.

## Steps (every invocation)

1. **Read the index completely:** `~/.agents/AGENTS.md` (or where it is aliased or symlinked from).
2. **Validate inventory:** enumerate every top-level `*.md` file in `~/.agents/rules/` without recursing. Extract the linked top-level rule paths from the index and compare the discovered inventory with the indexed inventory. Treat a missing, orphaned, duplicate, or unreadable indexed path as an error; do not silently skip it.
3. **Select startup/task rules:** select every rule in the index's `Always on` section plus every rule under a task-conditional `Activate` heading whose trigger matches the current request, repository, runtime, or intended tools. Exclude every `Action-gated` rule from task-start selection even when the request says that matching work will happen later. Selection follows index order; numeric prefixes provide the deterministic fallback.
4. **Read selected rules completely:** read every selected rule in one pass. Loading is complete only when the selected count equals the successfully read count.
5. **Absorb silently:** do not summarize, echo, or confirm the rulebook to the user.
6. **Apply rulebook-side semantics:** loading a rule is distinct from applying it. Honor each loaded rule's declared applicability and the index heading that selected it.
7. **Re-evaluate later requests:** before acting on each later user request, compare its scope with the task-conditional headings retained from the index. Read any newly applicable task-conditional rule completely before proceeding; do not reread rules already present unless context was compacted or the user explicitly re-invoked this skill.
8. **Open action gates just in time:** immediately before each operation, compare it with the retained `Action-gated` headings. Read every newly matching action-gated rule completely before beginning that operation's workflow or running its first command. A future operation named in a broader request is not enough to open the gate during earlier work. Once loaded, keep the rule active until compaction.

## Behavior

- **User's agent rulebook = complete index + validated inventory + applicable rules.** Inventory validation is exhaustive; content loading is eager, task-conditional, or action-gated according to the index.
- **Always-on means eager.** Read every rule in the `Always on` section completely on each invocation.
- **Task-conditional means request-time.** Read every matching `Activate` rule completely before task action, including rules that become applicable on later requests.
- **Action-gated means operation-time.** Read every matching action-gated rule immediately before the matching operation, never at startup solely because it is planned later.
- **Silent operation.** No user-visible output unless explicitly asked about the rulebook.
- **Compaction = reload.** Any turn after compaction should treat loading the user's agent rulebook as required, not optional.
