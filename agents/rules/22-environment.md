# 22 — Environment & package managers

Activate when code is involved.

## Node binaries

- When invoking `node` or `npx` — MCP source configs, skills, browser automation, scripts — use `~/.local/bin/node-stable` and `~/.local/bin/npx-stable`. Never resolve through nvm directly.

## Package managers

- **Detect before installing.** Check the project root for `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`, or `package-lock.json` — and `packageManager` in `package.json`. Use that manager. Never switch managers unasked (no `npm install` in a pnpm repo, no `yarn add` in a bun repo).
- **Never commit a second lockfile.** If you see a conflicting lockfile appear as a side-effect of a tool, delete it before staging.
- **Respect workspace protocols.** In workspaces, cross-package deps use the manager's workspace syntax (`"workspace:*"` for pnpm/yarn, `"workspace:*"` for bun). Don't replace with pinned versions "to be safe."

## Other ecosystems

- **Python** — detect `pyproject.toml`, `requirements.txt`, or `setup.py`. Prefer `uv` if `uv.lock` is present; otherwise use `pip` inside the active virtualenv. Never install packages globally. Activate the venv before running scripts.
- **Rust** — use `cargo` exclusively. Check `Cargo.toml` for workspace structure before adding dependencies. Never edit `Cargo.lock` by hand.
- **Go** — use `go mod` commands. Never edit `go.sum` by hand; let `go mod tidy` manage it. Respect the module root.

## Monorepos

- **Install at the right scope.** Add a dep to the package that actually imports it — not the root — unless it's a genuinely shared devDependency (linter, TS, test runner). Use the manager's filter flag: `pnpm add <dep> --filter <pkg>`, `yarn workspace <pkg> add <dep>`, `bun add <dep> --cwd packages/<pkg>`.
- **Run scripts via the workspace runner**, not by `cd`-ing into a package. `pnpm --filter <pkg> <script>` or `turbo run <script> --filter=<pkg>` — keeps task graphs and caching intact.
- **Don't hoist deliberately.** If a package doesn't declare a dep in its own `package.json`, don't rely on it being hoisted from the root. Add it to the package that needs it.
- **Respect the task runner.** If the repo has Turborepo, Nx, or Moon configured, use it for build/test/lint. Don't bypass with direct package scripts — pipelines exist for dependency ordering and cache reuse.
- **Never run a root-level `install` as a fix.** If installs misbehave, diagnose (stale store, version drift, peer-dep conflict) — don't `rm -rf node_modules && reinstall` as reflex.
