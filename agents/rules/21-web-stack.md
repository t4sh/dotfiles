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

"Run on localhost" and "show localhost preview" both request a browser preview. Unless the user explicitly supplies an exact URL or authorizes an exception, the required browser URL is a short, distinct `https://<name>.test` hostname through Portless on standard HTTPS port 443, with no port number in the URL.

1. Check `portless list` and proxy/service settings before starting a server. Reuse a working route; preserve other projects' routes. The shared proxy must use HTTPS, port 443, and `.test`. A numbered or HTTP proxy does not satisfy this requirement. Changing a shared proxy requires accounting for existing previews; do not disrupt them silently.
2. Keep shared project scripts and configuration unchanged for this personal preference. From the repo root, wrap the existing development command with `portless run --name <short-name> <command>`, or register an already-running server's observed port with `portless alias <short-name> <port>`. Choose a distinct name for concurrent projects/worktrees. Inspect runner behavior and pass Portless's assigned port explicitly if the runner ignores `PORT`.
3. If a host preview tool would open `http://localhost:<port>`, register the server's observed port with `portless alias` and open the Portless URL instead. Never present the tool's localhost default as the preview. Don't edit project launch files for this.
4. Obtain the actual route with `portless get <name>`. Verify HTTPS certificate trust, hostname resolution, and the rendered page in the browser before sharing the URL. Use `portless hosts sync` for unresolved `.test` hostnames; never invent a URL or hide a reported port. A raw HTTP check is insufficient.
5. If Portless, TLS trust, hostname resolution, or port 443 is unavailable, attempt the authorized host-native repair. If repair requires user authentication or would disrupt another preview, report the specific blocker and required action. Keep the preview incomplete until repaired or the user explicitly approves a fallback; never silently open or present a numbered localhost/HTTP URL as the completed preview.

On this Mac, retain the Portless startup service configured for HTTPS, port 443, and `.test`, so the same URL policy survives restart. Inspect `portless service status` before changing it; machine service state stays outside project repositories.
