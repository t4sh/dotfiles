# Rendered interface review contract

Load this contract for a complete or narrow interface review, including applied screen copy or typography. A complete review also loads the [shared quality contract](quality.md) for its aesthetic gate and designer-eye criteria; a narrow domain review does not. Inspect the rendered surface and use [Frontend verification](../../24-frontend-verification.md) for affected viewports, interaction, accessibility, and motion.

| Request | Primary owner |
| --- | --- |
| Review a complete screen, flow, feature, or product interface | `better-interface` |
| Review UI changes at a Git fixed point | `better-interface` |
| Focus, keyboard, ARIA, forms, screen readers, hit areas, reduced motion | `better-accessibility` |
| Grouping, alignment, reading order, responsive layout, RTL | `better-layout` |
| Product labels, errors, settings, empty states, and microcopy | `better-writing` |
| Font choice, rendering, hierarchy, wrapping, truncation, bidi | `better-typography` |
| OKLCH, palettes, contrast, gamut, semantic color | `better-colors` |
| Surfaces, radius, shadows, icons, micro-interactions, and UI finish | `better-ui` |

Use `better-interface` only for holistic coverage, including Git-fixed-point UI reviews. Route a narrow request directly to one domain owner. Prefer `interface-review` only when the user names it; it may resolve the diff first, then hand visual findings back. General correctness, tests, and security remain with `code-review`; visual and experiential quality remains with the design owner.

Required artifact: prioritized, evidence-backed findings and remediation guidance for review, or an applied change with in-context verification when implementation is authorized.
