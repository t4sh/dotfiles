# 11 — Skill routing

Always on. Apply before loading or invoking overlapping installed skills. Installed and third-party skill descriptions are retrieval hints; after any host-level selection, this rule is the local authority for assigning the owner, containing secondary material, and resolving overlap.

## Selection rules

1. **Explicit invocation wins.** When the user names a compatible installed skill, use it. If it is unavailable or incompatible with the deliverable, say so instead of silently substituting another.
2. **One primary owner by default.** Select the smallest sufficient skill. Do not stack skills merely because their descriptions share keywords.
3. **Route by deliverable, not topic.** Distinguish audit, specification, implementation, migration, documentation, and verification even when they concern the same domain.
4. **Sequence distinct phases.** When more than one skill is justified, assign each a non-overlapping phase such as specification → implementation → verification. Do not let multiple skills independently redesign the same solution.
5. **Orchestration must be intentional.** `better-interface` may coordinate its six owning `better-*` domains for an explicitly holistic review. Otherwise add a secondary skill only when it supplies a distinct requested artifact or verification pass.
6. **Project authority still wins.** Follow project instructions, existing tokens, components, conventions, and user scope over any skill default.
7. **Design work stays design-led.** For a user-facing interface, the design posture and selected design reference define the mode, artifact, and quality bar. Repository and Git workflows support the work but do not become its owner or dominate the response.

## Startup exceptions

Domain owners live in the conditional references below. Only these cross-domain routes stay here:

| Request | Owner |
| --- | --- |
| Implement a sufficiently specified change or execute an existing written plan | Core workflow when no conditional route matches; no manufactured skill gate |
| Browser verification or interaction | `04-codex-host-tooling.md` and its host-first ladder |
| PDF extraction or RAG | `pdf-harvester` |
| Paseo operation | `paseo` or its named subskill |

## Browser ladder

Use the connected or host browser for an existing profile, authentication, or localhost state; otherwise follow `04-codex-host-tooling.md` once its trigger activates.

## Installed-skill references

Cross-skill references inside an installed skill are advisory only. Follow one when the named skill is installed, compatible, and permitted here; missing siblings never trigger search, installation, or substitution.

The following skills are retired and must not be invoked even when third-party instructions mention them: `brainstorming`, `writing-plans`, `feature-dev`, `executing-plans`, `finishing-a-development-branch`, `writing-skills`, `skill-development`, and `systematic-debugging`.

## User-invoked preferences

Prefer these only when the user names the skill or unmistakably requests its method. Host auto-loading remains bounded reference material; project authority and the selected owner still control. Keep this policy here; never edit installed skill files to impose local routing policy.

`debug` `ponytail` `ponytail-help` `implement` `skill-creator` `to-spec` `to-tickets` `wayfinder` `interface-review` `variant` `pick-ui-library` `review-animations` `emil-design-eng` `ui-ux-pro-max` `creative-design` `minimalist-ui` `industrial-brutalist-ui` `redesign-existing-projects` `stitch-design-taste` `hallmark` `gpt-taste`

## Conditional routing references

Load the smallest matching reference; load multiple only for independent artifacts, in phase order:

| Task area | Reference |
| --- | --- |
| Non-interface planning, typed-semantic AI or explicitly requested test-first work, source review, minimalism, debugging, architecture, or skill authoring | [Development routing](routing/development.md) |
| UX architecture, research, synthesis, prototyping, or handoff | [UX routing](routing/design-ux.md) |
| Rendered interface direction, implementation, review, applied screen copy or typography, or creative work | [Interface routing](routing/design-interface.md) |
| Design systems, tokens, reusable type/copy authorities, font research, or conversion copy | [System/content routing](routing/design-system.md) |
| Animation and motion | [Motion routing](routing/motion.md) |
| Brand and static visual artifacts | [Artifact routing](routing/artifacts.md) |

The reference refines selection; it does not add another owner automatically. Return to the one-primary-owner rule after reading it.
