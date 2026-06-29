# 25 — Tech stack discovery (multi-runtime / cross-boundary)

Activate when a task touches a repo with multiple runtimes, native code, generated outputs, CLI/desktop UI, bindings, or service boundaries.

## Read manifests first

Before editing anything, read the manifests that define the repo's shape: `package.json`, `Cargo.toml`, `pyproject.toml`, `requirements.txt`, `tauri.conf.json` / `tauri.conf.json5`, lockfiles, and workspace config. Understand what runtimes are present and how they relate before touching any layer.

## Identify the layer before editing

Name the layer your change lives in before making it:

- **Browser UI** — webview, React/HTML/CSS, frontend assets
- **Desktop shell** — Tauri webview host, window management, OS integration
- **Rust backend** — Tauri commands, systems code, CLI binaries
- **Python backend** — scripts, services, data pipelines, ML inference
- **CLI / terminal UI** — argument parsing, prompts, streaming output, command help
- **Bindings / generated artifacts** — FFI, PyO3, WASM, protobuf, OpenAPI, codegen output
- **Service boundary** — HTTP APIs, IPC, message queues, event streams

Changes that cross a layer boundary require reading both sides first.

## Tauri projects

Check all of the following before editing:

- **Frontend** (`src/`, webview code) — see `21-web-stack.md` for rules
- **`src-tauri/`** — `tauri.conf.json`, `capabilities/`, `permissions/`, `Cargo.toml` plugin list
- **Commands** — Rust `#[tauri::command]` signatures; any type change here is a contract change with the frontend
- **Plugins** — each `tauri-plugin-*` in `Cargo.toml` must match the `@tauri-apps/plugin-*` frontend import; adding or removing either side alone breaks the app silently
- **Packaging impact** — `tauri.conf.json` bundle config, icons, deep link schemes, and updater settings affect release artifacts, not just dev

## Rust / Python bindings

When changing types, schemas, serialization formats, file paths, or error shapes that cross a language boundary (PyO3, WASM, FFI, REST, protobuf, JSON):

- Read both sides of the boundary before changing either
- Verify the serialization contract matches (field names, enums, optionality, error codes)
- Generated bindings files/packages (`*.pb.go`, `*_pb2.py`, generated client packages) are outputs — edit the source schema, not the generated output directly

## CLI and terminal UI

Treat CLI surfaces as UI. Apply the same completeness standard as browser UI:

- **Labels and prompts** — must be written in user language, not internal identifiers
- **Streaming output** — check truncation, line wrapping, and behavior when piped or redirected
- **Narrow widths** — terminals default to 80 columns; layout and tables must degrade gracefully
- **Empty / error states** — no output when nothing matches is a state; an unhelpful error message is a UX failure
- **Command help** (`--help`, subcommand trees) — part of the interface contract; keep it accurate when changing behavior

## Design and UX investigations

When investigating a user-facing issue or reviewing UI/UX, include backend files when they shape what the user sees or can do:

- API response shapes and error codes (determine visible states and copy)
- Permission and capability configs (determine what actions are available)
- Schema and data model constraints (determine field limits, formats, required vs. optional)
- Latency sources and loading boundaries (determine perceived responsiveness)
- Workflow sequencing in backend logic (determine what the user must do in what order)

Flag backend constraints that block a design goal rather than working around them silently in the frontend.

## Verification

Don't run broad builds by reflex. Match the verification scope to the layer changed:

- Frontend-only change → browser preview or component test
- Rust command change → `cargo test` for the changed crate, then integration test if the command is called from the frontend
- Binding / schema change → verify both sides compile and the contract still matches
- CLI change → run the affected subcommand with representative inputs including edge cases
- Cross-layer change → verify each layer independently, then the integration path
