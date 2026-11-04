# 24 — Frontend verification

Activate for web UI changes, review, or verification.

Review and verification include existing UI without code changes. A preview-only request uses rule 21 for its URL/opening procedure; it does not require a full UI audit. Match checks to the requested scope.

- **Skip when there is no user-facing surface.** Absent an explicit UI review/verification request, documentation-only edits, comments, tests, backend-only changes, dependency metadata, or trivial text/config changes that cannot affect rendered UI do not need browser verification. Report the actual reason for skipping.
- **Open the UI when feasible.** Use the available browser/tooling path to inspect the affected route or component in a real render, not just source code.
- **Check responsive states.** Verify at least one desktop and one mobile/narrow viewport for meaningful layout changes. Add tablet/wide checks when the layout has breakpoints there.
- **Check interaction states.** Exercise the primary hover, focus, active, loading, empty, error, and disabled states that the change affects.
- **Guard against visual regressions.** Look for text overflow, clipped controls, incoherent overlap, layout shift, missing assets, blank canvases, and contrast that appears marginal.
- **Accessibility is part of done.** Confirm semantic controls, labels, keyboard reachability, visible focus, and motion/animation behavior for the changed surface.
- **Keep motion purposeful.** Motion should provide feedback, orientation, continuity, or deliberate delight without delaying frequent tasks.
- **Respect motion safety.** Honor reduced-motion preferences and avoid effects likely to trigger vestibular discomfort.
- **Use efficient motion primitives.** Prefer transforms and opacity, avoid layout thrashing and broad `transition: all`, and use the project's motion tokens when they exist.
- **Verify motion under real interaction.** Check interruption, touch input, and representative low-end performance for meaningful animation changes.
- **Verify paired motion states.** Exercise the affected enter/exit, hover/focus, and press/release pairs rather than checking only the initial transition.
- **Report the preview target.** When a local or deployed preview was used, include the route/URL and the viewports or interactions checked.
