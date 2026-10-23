# Development skill routing

Load this reference for non-interface planning, typed-semantic AI or explicitly requested test-first work, source review, minimalism, debugging, architecture, or skill authoring. Other sufficiently specified implementation stays on the core workflow.

## Discovery, specifications, implementation, and planning

| Request | Primary owner |
| --- | --- |
| Interview or stress-test an unclear plan, decision, or idea | `grilling` |
| Design a system, API, data model, or service boundary | `system-design` |
| Build, extend, or explore an AI feature with typed semantic judgments | `typesafe-ai` |
| Record or evaluate one architecture decision and its trade-offs | `architecture` |
| Synthesize an already-settled conversation into a tracker specification | `to-spec` — explicit invocation only |
| Produce an executor-ready implementation plan for known work | `improve` in `plan <description>` mode |
| Break a plan or specification into tracker-native vertical slices | `to-tickets` — explicit invocation only |
| Map work too large or uncertain for one agent session | `wayfinder` — explicit invocation only |
| Use an explicitly requested test-first workflow with a red-green loop and agreed seams | `tdd` |
| Review a substantial fixed-point diff for correctness, behavior, security, or tests | `code-review` |

Boundaries:

- A sufficiently specified action request proceeds through the core workflow after reading relevant context. Do not manufacture a discovery, architecture, planning, TDD, multi-agent, or review approval gate.
- Use `typesafe-ai` when TypeSafe is requested or already integrated, and for features where routing, ranking, extraction, scoring, or verification needs semantic judgment. Read its current docs for the chosen integration. Do not route ordinary TypeScript typing, deterministic rules, or every AI feature to it.
- Local Codex/macOS: load TypeSafe credentials only for API commands, through `~/.dotfiles/bin/typesafe-env -- COMMAND [ARG...]`.
- Disposable uncertainty prototypes are owned by [UX routing](design-ux.md); do not select an owner from this file.
- `to-spec`, `to-tickets`, and `wayfinder` require explicit user invocation. `to-spec` synthesizes settled context and does not conduct the interview itself.
- `improve plan` authors the plan but does not own execution. `to-tickets` owns tracker decomposition and dependency edges, not file-level instructions.
- `tdd` owns an explicitly requested test-first workflow. It is not a prerequisite for ordinary implementation.
- `code-review` owns correctness, behavior, security, and test coverage for substantial, high-risk, or spec-backed fixed-point reviews. When the diff affects a rendered interface, sequence a `better-interface` pass for visual and experiential quality; source review does not substitute for rendered verification. Use the core read-only workflow for small ordinary diffs. Add `code-review-nextjs` only when a distinct framework-conventions pass is material.
- Do not auto-route to the user-invoked `implement` skill. Project rules override it when explicitly invoked, including commit authorization.

## Minimalism and over-engineering

| Request | Primary owner |
| --- | --- |
| Explicitly request Ponytail, lazy mode, or the smallest possible implementation | Core implementation workflow with `ponytail` as an explicit behavior modifier |
| Review a diff only for unnecessary complexity or deletion opportunities | `ponytail-review` |
| Audit a whole repository only for over-engineering or removable bloat | `ponytail-audit` |
| Show the installed Ponytail command reference | `ponytail-help` |

- Do not auto-route `ponytail` for ordinary coding work despite its broad upstream description.
- Ponytail may minimize implementation, never the acceptance boundary, project workflow, safety, accessibility, or required verification.
- A complete fixed-point review remains owned by `code-review`; use `ponytail-review` as a separate complexity-only pass when both are explicitly requested.
- A broad codebase audit remains owned by `improve`; use `ponytail-audit` only for a narrower delete/simplify report.
- `ponytail-help` is reference material only and does not activate a mode.

## Completion and integration

`07-worktree-lifecycle.md` is the sole authority for finishing development work, integration, pull requests, and branch/worktree cleanup. `03-worktree-hygiene.md` remains the always-on checkout-safety kernel. Do not invoke retired completion workflows.

## Phase procedures and continuity

Use these procedures inside the selected owner; they add no skills, mandatory phases, or approval gates. Skip phases the request does not need.

| Phase | Procedure | Completion evidence |
| --- | --- | --- |
| Discovery | Ask for concrete examples; distinguish the observed problem from the proposed solution; challenge load-bearing assumptions. | Settled problem, constraints, assumptions, and cheapest useful validation |
| Planning | Compare materially different approaches when useful; recommend holding, reducing, or expanding scope explicitly. Trace contracts, failure paths, recovery, and verification. | Accepted scope and acceptance criteria; expansion remains a proposal until authorized |
| Inspection | Compare intent with the actual diff; report missing requirements and unrelated changes separately from defects. Reproduce or trace each finding before reporting it. | Findings with evidence, impact, and unresolved limitations; no product edits without authorization |
| Verification | Consume the accepted criteria and prior findings; reproduce, then repair only when authorized, and rerun the original probe plus adjacent behavior. | Passed, failed, and unrun checks tied to the tested content |

Carry phase results forward through the [verification and continuity contract](../23-verification.md); ordinary implementation uses that contract without loading this specialist reference.

## Skill authoring

Default: `skill-architect` for authoring and evaluating skills. Explicit requests select compatible installed skills; otherwise `skill-creator` and Skill Development are references. Preserve scope, authorization, and quality.

Every new or substantively updated shared skill must provide:

- a concrete trigger and scope;
- a reusable procedure with checkable completion criteria;
- required capabilities, permissions, dependencies, and platforms;
- isolated client-specific adapters with a supported equivalent or explicit stop;
- portable paths and explicit platform boundaries;
- representative verification, failure conditions, and recovery guidance.

Before marking a shared skill ready, check duplicate names, resolve references, run collection gates, exercise executable instructions against a safe fixture when feasible, and include positive and negative routing scenarios. Keep the entrypoint concise and label untested instructions.

## Debugging and software interfaces

Use `diagnosing-bugs` for hypothesis-driven bug and performance diagnosis. `debug` is explicit-invocation-only. Durable root-cause, layered-defense, condition-waiting, and failure-reassessment guidance lives in `20-code-posture.md` and `23-verification.md`.

Use `system-design` when the requested interface is a module or API boundary. When alternatives are requested, compare distinct signatures and trade-offs before implementation. `better-interface` owns visual UI review, not module/API design.

## Review and advisory work

| Request | Primary owner |
| --- | --- |
| Current Vercel Web Interface Guidelines compliance | `web-design-guidelines` |
| Whole-codebase bugs, security, performance, tests, architecture, roadmap, or executor-ready plans | `improve` |

Use `web-design-guidelines` only for an explicit current external-standards pass. `improve` is a read-only advisor and plan author, not an interface implementer.
