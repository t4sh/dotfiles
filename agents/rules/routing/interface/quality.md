# Shared rendered-interface quality contract

Use for implementation, complete review, and creative work; skip for narrow domain reviews.

## Aesthetic quality gate

Check every affected dimension. Substantial new or redesigned surfaces must pass visual thesis, hierarchy, and accessibility. Narrow polish preserves the thesis and must pass affected hierarchy and accessibility checks. Landing pages, marketing, and brief-specific visual direction require distinctiveness.

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

After the first functional render, critique and correct three levels before completion:

1. **Macro:** On first look, identify the screen's apparent purpose, focal point, and invited action. Compare with the brief. Correct consequential mismatches in composition, silhouette, focal path, fold, hierarchy, density, or balance so the primary task reads before component detail.
2. **System:** grid, alignment logic, spacing rhythm, type scale, color ratios, surface relationships, and repeated component geometry. Repetition must feel intentional rather than copied from defaults.
3. **Micro:** optical alignment, baselines, wrapping, icon weight, borders, radii, control proportions, focus, hover, transition timing, and edge-state finish.

On the final render, look for copy that repeats the heading and for badges, icons, borders, shadows, or motion that duplicate an existing cue. Remove them when the task, meaning, state, and accessibility remain clear.

Re-render after corrections. For narrow changes, inspect the affected level in context. Finish when visible choices feel intentional, the product-specific signature survives representative viewports, and the interface works and looks finished.
