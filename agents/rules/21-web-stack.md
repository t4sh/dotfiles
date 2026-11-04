# 21 — Web stack rules (Tailwind + shadcn/ui + Next.js + React)

Activate for web UI changes, review, verification, or previews.

This includes starting/opening a browser preview without changing code. A web project's presence alone is insufficient; prose-only planning and unrelated documentation/backend work leave this rule deferred. Inspect the actual framework before applying framework-specific advice.
This covers browser-rendered frameworks and static HTML, including React, Next.js, Vite, Astro and Eleventy.

- **Read the stack before touching a component.** Check: the framework (React, SolidJS, vanilla HTML), the rendering model, the Tailwind version (v3 config vs v4 `@theme`), and whether the project uses a custom token system or raw utilities. The differences that matter live in the config and the component tree.
- **Fix patterns, not symptoms.** Before changing a UI component, read its parent, children, and any linked/shared components to understand the full rendering context. Don't patch presentation with conditional wrappers or attribute overrides when the real issue is in layout, data flow, or a parent's responsibility. The fix should make the component tree cleaner, not add another branch to it.
- No magic numbers. If you're writing `px-[18px]` in a system with a 4px base grid, stop — use `px-4` (16px), `px-5` (20px), or flag the inconsistency.
- Don't introduce new design tokens or component variants without checking if equivalents already exist.
- Don't "clean up" the Tailwind classes of components you weren't asked to touch.
- Map CSS custom properties to `tailwind.config` / `@theme` directives cleanly. Name tokens so a React port is mechanical, not creative (`ds-card`, `ds-button-primary`).
- Flag contrast failures the moment they look marginal. Don't wait for an audit.
- Preserve accessibility while changing UI: keyboard focus, semantic elements, labels, ARIA only when needed, and visible state changes are part of the component contract.
- For React/Next.js, check the rendering boundary before moving code: server/client components, hydration behavior, route conventions, metadata, and data-fetching constraints are load-bearing.
- When documenting UI, use a token map or component contract as the implementation artifact. Judge visual quality from rendered evidence, not source structure alone. Screenshots support static visual review but do not prove interaction, responsiveness, or state behavior. See `10-design-posture.md`.

## Local preview URLs

"Run on localhost" and "show localhost preview" both request a browser preview. Unless the user supplies an exact URL, use installed Portless for the browser URL. Prefer a short, distinct `https://<name>.test` URL with the proxy on standard HTTPS port 443, so the browser URL needs no port number. Configure `.test` and port 443 when starting a new proxy; check existing proxy settings and routes before changing a running proxy. Portless may fall back to port 1355 when privileged port 443 startup cannot complete; treat that as a fallback, not the preferred URL. Treat a repo's documented `http://localhost:<port>` as an upstream, not the final preview. Start new servers through Portless from the repo root, or alias each running server's observed port after checking `portless list`. Pass the assigned port if a runner ignores `PORT`. Open and verify the actual URL Portless reports (`portless get <name>` for aliases); never omit a reported nonstandard port or substitute an unverified short URL. If the preferred proxy setup would disrupt existing routes or needs privileges that are unavailable, use the working reported URL and explain the constraint. If a `.test` hostname does not resolve, run `portless hosts sync`. A raw HTTP check is insufficient. If Portless is unavailable, use the repo URL.
