# Rendered interface review contract

Inspect the rendered surface using [Frontend verification](../../24-frontend-verification.md). A complete review also loads the [shared quality contract](quality.md).

| Request | Primary owner |
| --- | --- |
| Review a complete screen, flow, feature, or product interface | `better-interface` |
| Review UI changes at a Git fixed point | `better-interface` |
| Stress-test a component with extreme content or reachable states | Frontend verification. Use the relevant domain owner for requested diagnosis or fixes. |
| Focus, keyboard, ARIA, forms, screen readers, hit areas, reduced motion | `better-accessibility` |
| Grouping, alignment, reading order, responsive layout, RTL, viewport sizing and safe areas | `better-layout` |
| Product labels, errors, settings, empty states, and microcopy | `better-writing` |
| Font choice, rendering, hierarchy, wrapping, truncation, bidi | `better-typography` |
| OKLCH, palettes, contrast, gamut, semantic color | `better-colors` |
| Surfaces, radius, shadows, icons, micro-interactions, touch feedback, and UI finish | `better-ui` |

Use `better-interface` for holistic coverage, including Git-fixed-point UI reviews. Use one domain owner for narrow work. Explicitly named `interface-review` may resolve the diff and hand visual findings back. General correctness, tests, and security belong to `code-review`.

Required artifact: prioritized, evidence-backed findings and remediation guidance for review, or an applied change with in-context verification when implementation is authorized.
