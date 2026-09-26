# Design system, typography, and writing routing contract

Load this reference for design systems, tokens, reusable component libraries, palettes, reusable type/copy authorities, font research, or conversion copy.

## Select system or content mode

Choose by artifact. Reusable authorities, libraries, tokens, palettes, and type systems use system mode; font research and conversion copy use content mode. Applied screen copy or typography belongs to the interface design route. A one-off content change stays with its narrow consumer instead of expanding into system work.

## Design systems and tokens

1. **Inspect.** Read project design authorities, tokens, components, and representative consumers. Done when coverage, drift, and constraints can be named.
2. **Select.** Choose one route and artifact. Done when its boundary and acceptance criteria are explicit.
3. **Execute.** Change the owning system rather than isolated consumers. Done when the requested scope is covered without a parallel authority.
4. **Verify.** Check the artifact against its source and representative consumers. Use [Frontend verification](../24-frontend-verification.md) when rendered components change. Done when evidence is recorded or unavailable checks have an executable handoff.

| Request | Primary owner |
| --- | --- |
| Audit, document, or extend an entire component system | `design-system` |
| Measure hard-coded values, token adoption, duplicates, deprecations, or gaps | `design-token-audit` |
| Generate portable static CSS, JSON, or theme tokens | `design-tokens` |
| Implement a Tailwind CSS v4 component library or migrate Tailwind v3 → v4 | `tailwind-design-system` |
| Generate or assess only palettes, contrast, gamut, or color semantics | `better-colors` |

Audit the reusable system with `design-system` and a rendered screen or flow with `better-interface`. Use `design-token-audit` for quantitative inventory, `design-tokens` for portable output, and `tailwind-design-system` for Tailwind v4 implementation. Load the interface design route only when the request also requires a screen or flow artifact.

Required artifact: a system audit, token package, working library or migration, or palette specification with verification evidence.

## Typography and writing

This route owns reusable type/copy authorities, font research, and conversion copy — not applied screen copy or typography.

- Use `design-system` for reusable type/copy authorities.
- Use `web-typography` for typeface evaluation, pairing research, licensing, loading, subsetting, and payloads.
- Use `copywriting` when copy persuades someone to choose, buy, or convert.

Required artifact: a reusable type/copy authority, conversion copy, or an evidence-backed font recommendation with acceptance criteria.
