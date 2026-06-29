# 23 — Verification before completion

Activate when code, config, automation, data transforms, or generated artifacts are changed.

- **Verify the behavior you touched.** Run the narrowest meaningful test, build, lint, typecheck, script, preview, or command that proves the requested change works.
- **Prefer project-defined commands.** Use the repo's documented verification path first. If none exists, choose the smallest local check that exercises the changed surface and say what it covers.
- **Do not claim unrun checks.** Report exactly what passed, failed, or was skipped. If a check could not run because of missing deps, network, credentials, time, or sandbox limits, say so plainly.
- **Investigate failures in scope.** If a verification command fails, determine whether the failure is caused by your change, pre-existing state, environment, or an unrelated area before reporting it.
- **Keep evidence concise.** Summarize the important command names and outcomes; include raw output only when the specific lines explain the result.
