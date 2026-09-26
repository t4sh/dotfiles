# 22 — Environment dispatcher

Activate when code is involved.

Before package, runtime, dependency, or setup commands, inspect manifests and lockfiles. Load task-touched ecosystems in one pass; load every relevant ecosystem only for repo-wide setup or cross-runtime work. With no match, load none. Add monorepo only when workspace configuration or package layout proves it.

| Evidence or intended command | Reference |
| --- | --- |
| `package.json`, Node lockfile, `node`, `npm`, `pnpm`, `yarn`, `bun`, `npx` | [Node and package managers](environment/node.md) |
| `pyproject.toml`, `requirements.txt`, `setup.py`, Python or `pip` | [Python](environment/python.md) |
| `Cargo.toml`, Rust or `cargo` | [Rust](environment/rust.md) |
| `go.mod`, Go or `go` | [Go](environment/go.md) |
| Workspace configuration, multiple packages, Turborepo, Nx, or Moon | [Monorepos](environment/monorepo.md) |

Use the repository workflow; ignore unrelated global tools.
