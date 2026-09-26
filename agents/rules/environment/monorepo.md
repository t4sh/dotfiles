# Monorepo environment contract

- **Install at the importing package**, not the root unless genuinely shared tooling; use the manager's workspace/filter command.
- **Run scripts through the workspace runner** so dependency order and caching remain intact.
- **Declare every imported dependency;** never rely on hoisting.
- **Respect the task runner.** Use the configured Turborepo, Nx, or Moon build, test, and lint pipeline.
- **Diagnose install failures.** Do not reflexively root-install or delete dependency state for store, version, peer, or configuration errors.
