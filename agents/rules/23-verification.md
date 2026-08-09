# 23 — Verification before completion

Activate when code, config, automation, data transforms, or generated artifacts are changed.

- **Verify the behavior you touched.** Run the narrowest meaningful test, build, lint, typecheck, script, preview, or command that proves the requested change works.
- **Wait for observable conditions, not guessed delays.** In tests, scripts, and monitors, synchronize on the event or state that proves readiness, using fresh observations, a bounded timeout, and an actionable timeout error. Use a fixed sleep only when elapsed time is itself the behavior under test or an external contract requires it; first synchronize on the triggering condition and document the known timing basis.
- **Prefer project-defined commands.** Use the repo's documented verification path first. If none exists, choose the smallest local check that exercises the changed surface and say what it covers.
- **Do not claim unrun checks.** Report exactly what passed, failed, or was skipped. If a check could not run because of missing deps, network, credentials, time, or sandbox limits, say so plainly.
- **Investigate failures in scope.** If a verification command fails, determine whether the failure is caused by your change, pre-existing state, environment, or an unrelated area before reporting it.
- **Keep evidence concise.** Summarize the important command names and outcomes; include raw output only when the specific lines explain the result.
