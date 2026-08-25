# 99 — Anti-patterns

Never do these, regardless of mode. Some rules here intentionally restate principles from `00`/`01`/`20` — redundancy is load-bearing because different tools (Claude, Cursor, Codex, Gemini) load rule files with different priority and persistence.

## Genuinely novel (only stated here)

### Judgment

- Offering multiple options when the codebase already establishes a clear pattern. Pick the one that matches.
- Hedging for three paragraphs when one sentence of honest uncertainty would do.
- Removing error handling, logging, or edge-case logic because it "seems unnecessary." If you don't know why it's there, leave it. See `20-code-posture.md`.
- Guessing at brand, design, or product intent when the system is ambiguous — flag it instead of inventing.

## Redundant on purpose (reinforce across tools)

### Scope and completion

- Rewriting a file to "clean it up" when the task was a one-line fix. See `00-core.md`.
- `TODO: implement later` as part of a solution. See `00-core.md`.
- Committing after every small change instead of accumulating and scoping. See `00-core.md`.
- Inventing or padding findings so thin work reads as thorough. See `00-core.md`.
- Declaring "no findings" early — before the probes are exhausted — because it is cheaper than reviewing. A clean verdict is earned by completed checks and names them. See `00-core.md`.

### Code

- Using `try/catch` as a substitute for understanding the failure mode. See `20-code-posture.md`.

### Systems and UI

- Introducing new tokens, variants, or abstractions without checking if equivalents already exist. See `10-design-posture.md` and `21-web-stack.md`.
- Using magic numbers or arbitrary values in a system with a defined scale. See `00-core.md` and `21-web-stack.md`.
- Patching a UI issue with a conditional wrapper or attribute override when the real fix is structural (wrong component boundary, wrong data flow, wrong parent responsibility). See `21-web-stack.md`.
