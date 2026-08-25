# 11 — Skill routing

Always on. Apply this before loading or invoking installed skills whose descriptions overlap.

## Selection rules

1. **Explicit invocation wins.** When the user names a compatible installed skill, use it. If it is unavailable or incompatible with the requested deliverable, say so rather than silently substituting another.
2. **One primary owner by default.** Select the smallest sufficient skill. Do not stack skills merely because their descriptions share keywords.
3. **Route by deliverable, not topic.** Distinguish audit, specification, implementation, migration, documentation, and verification even when all concern the same domain.
4. **Sequence distinct phases.** When more than one skill is justified, assign each a non-overlapping phase such as specification → implementation → verification. Do not let multiple skills independently redesign the same solution.
5. **Orchestration must be intentional.** `better-interface` may coordinate its six owning `better-*` domains for a holistic review. Otherwise add a secondary skill only when it supplies a distinct requested artifact or verification pass.
6. **Project authority still wins.** Follow project instructions, existing tokens, components, conventions, and user scope over any skill default.

## Written-plan execution

The **Executing written plans** section in `00-core.md` is the sole authority for implementing an existing written plan; `23-verification.md` and `03-worktree-hygiene.md` still govern verification and workspace/integration safety. Do not invoke the retired `executing-plans` skill, including when another third-party skill names it as a required handoff.

## Discovery, specifications, implementation, and planning

Do not invoke the retired `brainstorming`, `writing-plans`, or `feature-dev` skills. Route by the action or artifact the user needs:

| Request | Primary owner |
| --- | --- |
| Implement a sufficiently specified feature or change | Core workflow in `00-core.md`, `20-code-posture.md`, and `23-verification.md`; no workflow skill |
| Interview or stress-test an unclear plan, decision, or idea | `grilling` |
| Build throwaway UI or logic to answer one concrete design question | `prototype` |
| Design a system, API, data model, or service boundary | `system-design` |
| Record or evaluate one architecture decision and its trade-offs | `architecture` |
| Synthesize an already-settled conversation into a tracker specification | `to-spec` |
| Produce an executor-ready implementation plan for known work | `improve` in `plan <description>` mode |
| Break a plan or specification into tracker-native vertical slices | `to-tickets` |
| Map work too large or uncertain for one agent session | `wayfinder` |
| Implement explicitly test-first with a red-green loop and agreed seams | `tdd` |
| Review changes since a fixed commit, branch, tag, or merge-base | `code-review` |

Boundaries:

- A sufficiently specified action request proceeds through the core workflow after reading the relevant context. Do not manufacture a discovery, architecture, planning, TDD, multi-agent, or review approval gate.
- `prototype` resolves an uncertain design question with disposable evidence; it does not replace requirements discovery or a durable specification.
- `to-spec` synthesizes settled context and does not conduct the interview itself.
- `improve plan` authors the plan but does not own execution; use the written-plan execution authority above afterward.
- `to-tickets` owns tracker decomposition and dependency edges, not file-level implementation instructions.
- `tdd` owns an explicitly requested test-first workflow. It is not a prerequisite for ordinary implementation; `23-verification.md` still requires proportionate verification.
- `code-review` owns a requested fixed-point diff review. It is not an automatic completion phase; the proactive in-scope review in `00-core.md` still applies while implementing.
- Do not auto-route to the user-invoked `implement` skill. When the user invokes it explicitly, project rules still override its bundled defaults, including commit authorization.

## Minimalism and over-engineering

| Request | Primary owner |
| --- | --- |
| Explicitly request Ponytail, lazy mode, or the smallest possible implementation | Core implementation workflow with `ponytail` as an explicit behavior modifier |
| Review a diff only for unnecessary complexity or deletion opportunities | `ponytail-review` |
| Audit a whole repository only for over-engineering or removable bloat | `ponytail-audit` |
| Show the installed Ponytail command reference | `ponytail-help` |

Boundaries:

- Do not auto-route `ponytail` for ordinary coding work despite its broad upstream description. The core workflow already owns implementation; use Ponytail only when the user explicitly requests that discipline.
- Ponytail may minimize the implementation, never the requested acceptance boundary, project workflow, safety requirements, accessibility, or verification required by `23-verification.md`.
- A complete fixed-point review remains owned by `code-review`. When the user explicitly asks for both complete review and over-engineering review, run `ponytail-review` as a separate complexity-only pass rather than replacing or merging the Standards and Spec axes.
- A broad whole-codebase audit remains owned by `improve`; use `ponytail-audit` only for the narrower delete/simplify report.
- `ponytail-help` is user-invoked reference material only. Do not use it to activate a mode or route work.

## Development completion and integration

`03-worktree-hygiene.md` is the sole authority for finishing development work, integration, pull requests, and branch/worktree cleanup. Do not invoke the retired `finishing-a-development-branch` skill, including when a third-party skill names it as a required follow-up.

## Skill authoring and review

Use `skill-architect` for creating, editing, auditing, comparing, or evaluating agent skills. Do not route to the retired `writing-skills` skill; its reusable behavior-evidence principles are preserved in `skill-architect` references.

## Debugging

Use `diagnosing-bugs` for hypothesis-driven bug and performance diagnosis. Do not route to the retired `systematic-debugging` skill; its durable root-cause, layered-defense, condition-waiting, and three-failed-fixes guidance is preserved in `20-code-posture.md` and `23-verification.md`.

## Software interface architecture

Use `design-an-interface` when the requested interface is a module or API boundary and the deliverable is multiple radically different signatures/shapes with trade-off comparison. It is read-only design exploration, not visual UI design or implementation.

## Design systems and tokens

| Request | Primary owner |
| --- | --- |
| Audit, document, or extend an entire component system | `design-system` |
| Measure hard-coded values, token adoption, duplicates, deprecations, or gaps | `design-token-audit` |
| Generate portable static CSS, JSON, or theme tokens | `design-tokens` |
| Migrate static or Figma tokens into a reactive Design Book graph | `design-book` |
| Model Design Book refs, derived values, procedural tokens, modes, or dependencies | `design-book` |
| Implement a Tailwind CSS v4 component library or migrate Tailwind v3 → v4 | `tailwind-design-system` |
| Generate or assess only palettes, contrast, gamut, or color semantics | `better-colors` |

Boundaries:

- Audit the reusable system itself with `design-system`; audit a rendered screen or flow with `better-interface`.
- Use `design-token-audit` for quantitative inventory; do not substitute the broader `design-system` audit.
- Use `design-tokens` for static portable output. Use `design-book` only when Design Book is named, installed in the target, or explicitly selected as the migration target.
- For Tailwind v4 implementation, prefer `tailwind-design-system`; a prior `design-system` specification may feed it without being redesigned.

## Interface review domains

| Request | Primary owner |
| --- | --- |
| Holistic screen, flow, feature, or product-interface review | `better-interface` |
| Focus, keyboard, ARIA, forms, screen readers, hit areas, reduced motion | `better-accessibility` |
| Grouping, alignment, reading order, responsive layout, RTL | `better-layout` |
| Product-interface labels, errors, settings, empty states, microcopy | `better-writing` |
| Font choice, rendering, hierarchy, wrapping, truncation, bidi | `better-typography` |
| OKLCH, palettes, contrast, gamut, semantic color | `better-colors` |
| Surfaces, radius, shadows, icons, micro-interactions, UI polish | `better-ui` |

Use `better-interface` only for holistic coverage. Route a narrow request directly to its single domain owner.

## Typography and writing boundaries

- Use `better-typography` for rendered interface text and typographic behavior.
- Use `web-typography` for typeface evaluation, pairing research, licensing, FOUT/FOIT, preloading, subsetting, and font payloads.
- Use `better-writing` when copy helps someone operate a product.
- Use `copywriting` when copy persuades someone to choose, buy, or convert.

## Review, evidence, and advisory work

| Request | Primary owner |
| --- | --- |
| Current Vercel Web Interface Guidelines compliance | `web-design-guidelines` |
| Measured screenshot redlines, overlays, layout rails, visual QA artifacts | `ux-redline-audit` |
| Whole-codebase bugs, security, performance, tests, architecture, roadmap, or executor-ready plans | `improve` |

Boundaries:

- Use `better-interface` for a comprehensive interface judgment. Use `web-design-guidelines` for an explicit current external-standards pass; if both are requested, run them as separate passes.
- Use `ux-redline-audit` only when measured visual artifacts are requested, not as a substitute for a general design review.
- `improve` is a read-only codebase advisor and plan author, not an interface implementer.

## Motion

| Request | Primary owner |
| --- | --- |
| Polish motion in one component as part of broader UI detail work | `better-ui` |
| Design, implement, or debug production UI motion, gestures, drag, or springs | `ui-animation` |
| Reverse-engineer motion from a recording, fit curves, or name a described effect | `ui-animation` |
| Install a named portable CSS transition recipe or normalize motion to its token set | `transitions-dev` |
| Apply explicitly Apple/WWDC-style physical gestures, momentum, springs, or materials | `apple-design` |
| Discover where motion should exist (and reject where it should not); propose recipes without implementing | `find-animation-opportunities` |
| Review an existing motion diff or animation code against a strict bar | `review-animations` |
| Audit repository-wide motion and produce implementation plans | `improve-animations` |
| Create cinematic, scroll-driven, immersive motion | `top-design` |

Boundaries:

- Use `better-ui` for small polish within broader interface work; use `ui-animation` when motion itself is the implementation task.
- Use `transitions-dev` for its named recipes and token-refinement workflow, not as a general motion authority.
- Use `apple-design` only when Apple-style physical interaction is explicit, not as a default for routine product motion.
- Use `find-animation-opportunities` for read-only discovery of new motion moments ("what could be animated?", "make this feel more alive"). Do not use it to review or fix existing animations — that is `review-animations` / `improve-animations`.
- Do not use a repository-wide motion auditor for a single component, or cinematic direction for routine product interactions.

## Creative direction versus implementation

| Request | Primary owner |
| --- | --- |
| Implement, redesign, polish, harden, or iterate an interface | `impeccable` |
| Establish distinctive brief-specific visual direction | `frontend-design` |
| Landing page, portfolio, or visual redesign needing anti-template constraints | `design-taste-frontend` |
| Explicit Awwwards-level, cinematic, or immersive experience | `top-design` |

Select one primary creative workflow. Do not automatically stack these skills. Use domain skills afterward for focused verification when requested.

## Broad overlapping alternatives

Do not auto-route generic design requests to `emil-design-eng`, `ui-ux-pro-max`, `creative-design`, `minimalist-ui`, `industrial-brutalist-ui`, `redesign-existing-projects`, `stitch-design-taste`, `hallmark`, or `gpt-taste` when a canonical owner above fits. Use one of these only when the user invokes it explicitly or requests its exact named platform, method, or aesthetic deliverable.

Use `pick-ui-library` only when the user explicitly asks for a curated library recommendation (toasts, charts, DnD, virtualization, OTP, command menus, and similar). It does not auto-trigger; do not substitute it for general UI implementation or motion work.

## Brand and static visual artifacts

| Request | Primary owner |
| --- | --- |
| Apply Anthropic's official colors and typography to an artifact | `brand-guidelines` |
| Generate a brand identity board, logo system, identity deck, or brand-kit image | `brandkit` |
| Create original static poster/artwork as PNG or PDF | `canvas-design` |
| Apply a preset or custom theme to an existing slide deck, document, report, or similar artifact | `theme-factory` |

Do not use these artifact skills as application design-system or product-UI implementation authorities. `brand-guidelines` is Anthropic-specific, not a generic branding skill.
