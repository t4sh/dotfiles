# Shared rendered-interface quality contract

Use for implementation, complete review, and creative work; skip for narrow domain reviews.

## Aesthetic quality gate

Use this gate for rendered-interface work. Apply every dimension the change can affect. For a substantial new or redesigned surface, fail closed on visual thesis, hierarchy, and accessibility. For narrow product polish, preserve the existing thesis and fail closed on affected hierarchy and accessibility rather than adding novelty for its own sake. Distinctiveness is required for landing, marketing, and brief-specific visual direction.

Use the gate internally; do not emit a scored table unless the user requests one. Report failed dimensions, consequential design decisions, and rendered verification evidence.

| Dimension | Pass condition |
| --- | --- |
| Visual thesis | The interface has a recognizable point of view appropriate to its product, audience, and brand |
| Hierarchy | The primary task, next action, and supporting information are immediately distinguishable |
| Composition | Alignment, balance, density, whitespace, and section rhythm create intentional reading order |
| Typography | Type choice, scale, weight, measure, wrapping, and contrast create clear editorial hierarchy |
| Color and material | Semantic color, surfaces, borders, elevation, and imagery form a restrained coherent system |
| Detail | Radii, icons, dividers, controls, focus, hover, and transitions share consistent geometry and finish |
| Interaction | Feedback is immediate, state changes are legible, risky actions are recoverable, and motion explains change |
| Responsiveness | The composition adapts rather than merely shrinks; hierarchy and actions survive narrow and wide viewports |
| Accessibility | Keyboard use, focus, contrast, names, roles, target sizes, zoom, and reduced motion remain first-class |
| Distinctiveness | The result avoids interchangeable templates and contains a few memorable, product-specific decisions |

## Designer-eye pass

After the first functional render and before declaring frontend work complete, critique and correct it at three levels:

1. **Macro:** composition, silhouette, focal path, fold, hierarchy, density, and balance. The primary task must read before component detail.
2. **System:** grid, alignment logic, spacing rhythm, type scale, color ratios, surface relationships, and repeated component geometry. Repetition must feel intentional rather than copied from defaults.
3. **Micro:** optical alignment, baselines, wrapping, icon weight, borders, radii, control proportions, focus, hover, transition timing, and edge-state finish.

Re-render after corrections. On a narrow change, inspect the affected level plus its immediate context instead of redesigning the page. The pass is complete when no visible choice feels accidental, the product-specific signature survives representative viewports, and functional correctness is matched by visual finish.
