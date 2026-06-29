# 21 — Web stack rules (Tailwind + shadcn/ui + Next.js + React)

Activate when the project uses browser-rendered UI: Tailwind, shadcn/ui, Next.js, React, Vite, Astro, Eleventy, static HTML, or an equivalent web frontend. For Tauri, apply this file to the webview/frontend layer and use `25-tech-stack-discovery.md` for the native Rust side. Skip entirely for non-web projects.

- **Read the stack before touching a component.** Check: the framework (React, SolidJS, vanilla HTML), the rendering model, the Tailwind version (v3 config vs v4 `@theme`), and whether the project uses a custom token system or raw utilities. The differences that matter live in the config and the component tree.
- **Fix patterns, not symptoms.** Before changing a UI component, read its parent, children, and any linked/shared components to understand the full rendering context. Don't patch presentation with conditional wrappers or attribute overrides when the real issue is in layout, data flow, or a parent's responsibility. The fix should make the component tree cleaner, not add another branch to it.
- No magic numbers. If you're writing `px-[18px]` in a system with a 4px base grid, stop — use `px-4` (16px), `px-5` (20px), or flag the inconsistency.
- Don't introduce new design tokens or component variants without checking if equivalents already exist.
- Don't "clean up" the Tailwind classes of components you weren't asked to touch.
- Map CSS custom properties to `tailwind.config` / `@theme` directives cleanly. Name tokens so a React port is mechanical, not creative (`ds-card`, `ds-button-primary`).
- Flag contrast failures the moment they look marginal. Don't wait for an audit.
- Preserve accessibility while changing UI: keyboard focus, semantic elements, labels, ARIA only when needed, and visible state changes are part of the component contract.
- For React/Next.js, check the rendering boundary before moving code: server/client components, hydration behavior, route conventions, metadata, and data-fetching constraints are load-bearing.
- When documenting UI, prefer token maps and component specs over screenshots or prose descriptions — they're more implementable.

## Tauri apps

- **Respect the IPC boundary.** The frontend (React/HTML) communicates with Rust via Tauri commands — never reach for `window.__TAURI__` directly; use `@tauri-apps/api` wrappers. Don't call browser APIs (`fetch`, `localStorage`, DOM globals) for anything that needs filesystem, process, or OS access — route it through a Tauri command instead.
- **No DOM APIs in Rust command handlers.** Tauri commands run in the Rust backend; they have no DOM. If a handler needs to update UI state, emit an event the frontend listens to.
- **Plugin imports are load-bearing.** Each `@tauri-apps/plugin-*` package maps to a registered Rust plugin. Adding or removing a frontend import without the corresponding Rust-side change will silently fail at runtime.
