# Codex user bridge

At session start and after context compaction, invoke the `init-rulebook` skill to load and rehydrate the canonical user rulebook under `~/.agents/`.

When `~/.codex/RTK.md` exists, read it and apply its Codex-specific command guidance.
