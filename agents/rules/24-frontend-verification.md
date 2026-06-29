# 24 — Frontend verification

Activate when a task changes user-facing web UI, layout, styling, routing, or interaction.

- **Skip when there is no user-facing surface.** Documentation-only edits, comments, tests, backend-only changes, dependency metadata, or trivial text/config changes that cannot affect rendered UI do not need browser verification. Say it was skipped because no UI behavior changed.
- **Open the UI when feasible.** Use the available browser/tooling path to inspect the changed route or component in a real render, not just source code.
- **Check responsive states.** Verify at least one desktop and one mobile/narrow viewport for meaningful layout changes. Add tablet/wide checks when the layout has breakpoints there.
- **Check interaction states.** Exercise the primary hover, focus, active, loading, empty, error, and disabled states that the change affects.
- **Guard against visual regressions.** Look for text overflow, clipped controls, incoherent overlap, layout shift, missing assets, blank canvases, and contrast that appears marginal.
- **Accessibility is part of done.** Confirm semantic controls, labels, keyboard reachability, visible focus, and motion/animation behavior for the changed surface.
- **Report the preview target.** When a local or deployed preview was used, include the route/URL and the viewports or interactions checked.
