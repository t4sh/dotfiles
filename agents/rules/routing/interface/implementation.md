# Interface implementation contract

For visual direction or implementation, also load [shared quality](quality.md).

| Design request | Primary owner | Required artifact |
| --- | --- | --- |
| Establish a brief-specific visual direction before implementation | `frontend-design` | Visual thesis, composition, type, color, spacing, and motion direction |
| Implement, redesign, polish, or iterate a product interface | `impeccable` | Rendered interface plus state coverage and verification evidence |

## Interface operating sequence

1. **Inspect.** Read project design authorities and inspect the rendered product when available. Done when the current hierarchy, primary user task, visual system, reusable primitives, and material constraints can be named.
2. **Frame.** Select the mode, required artifact, primary user, primary task, and one coherent visual thesis. State evidence gaps as assumptions. Done when the artifact can be judged against a concrete direction rather than generic taste.
3. **Structure.** Resolve information hierarchy, interaction, content priority, and state behavior before decorative polish. Done when the primary flow and exceptional states have explicit behavior.
4. **Craft.** Apply typography, composition, spacing rhythm, color roles, surfaces, imagery, icons, and motion as one system. Done when every major decision reinforces the thesis and the product's identity.
5. **Verify.** Identify applicable material states from [Design posture](../../10-design-posture.md), then use [Frontend verification](../../24-frontend-verification.md) for the browser, viewport, interaction, accessibility, and motion procedure. Done when evidence is recorded or unavailable checks are named with an executable handoff.

## Frontend art direction

For a new or materially redesigned frontend, establish this compact internal brief before code. It is a working constraint, not mandatory user-facing prose.

| Decision | Required specificity |
| --- | --- |
| Product anchor | The audience, primary task, content character, brand truth, and emotional register the interface must express |
| Thesis | One sentence describing the intended visual and interaction character without generic adjectives alone |
| Signature move | One memorable compositional, typographic, material, imagery, or motion decision tied to the product—not decoration applied everywhere |
| System translation | The grid, type hierarchy, spacing rhythm, palette roles, surface geometry, imagery, and motion behavior that make the thesis repeatable |
| Rejection criteria | The template habits or inherited implementation choices that would weaken this particular direction |

If the user supplies a direction, sharpen and implement it rather than replacing it. Preserve brand meaning and valid system constraints, not accidental spacing, weak hierarchy, or low-quality component defaults. Run the specificity test before implementation: hide the logo and product copy; if the composition could belong to almost any product, revise the thesis or signature move.

Reject generic AI defaults: indiscriminate card grids, excessive pills, gratuitous gradients or glow, interchangeable centered heroes, arbitrary glass effects, and rhythm-free uniform spacing.

## Frontend pressure cases

| Request pressure | Required response |
| --- | --- |
| “Make it clean/modern” with no visual brief | Derive a product-specific thesis and signature move from audience, task, content, and brand; do not default to a generic SaaS shell |
| “Polish this component” | Preserve the established direction, inspect surrounding context, and correct the affected system and micro details without broad redesign |
| “Review this PR/UI diff” | Load the interface review contract, resolve the fixed point, render the affected surfaces, and keep visual findings design-owned; source review alone is insufficient |
| “Match this screenshot” | Extract the governing hierarchy and system, resolve inconsistencies, and verify responsive and interactive states rather than photocopying pixels |
| “Just make it work” on user-facing frontend | Respect the requested scope while preserving the system and running the applicable designer-eye and rendered-verification passes |
