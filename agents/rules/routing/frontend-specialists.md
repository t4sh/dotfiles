# Frontend specialists

Load for the specific frontend task below. Select one owner per phase; project
design authorities, package managers and runtime rules remain authoritative.

| Requested artifact | Owner | Boundary |
| --- | --- | --- |
| Measured website loading/interaction audit or performance optimization | `web-perf` | Works across frameworks, including Eleventy output. Discover browser trace capabilities first; report unavailable measurements. MCP setup requires authorized configuration scope. |
| Web UI implementation that depends on modern browser APIs, browser support/fallback decisions, or modernization of a legacy web pattern | `modern-web-guidance` | Search and retrieve in the implementation phase. This is platform guidance, not visual direction or a holistic UI review. Honor project runtime and browser policies; follow this narrower local trigger over the upstream skill's broader automatic trigger. |
| React component API/composition design or refactoring | `vercel-composition-patterns` | Compound components, state boundaries and boolean-prop growth; apply version-specific rules only to compatible React versions. |
| shadcn/ui component selection, composition, registry, preset or update work | `shadcn` | Use in shadcn projects or explicitly requested setup; preserve the project's component base, tokens and package runner. |

For a broad UI build/redesign, keep the existing interface owner and consult only
the relevant specialist references during its implementation phase. These skills
do not replace visual direction or holistic interface review. Generic module/API
architecture stays with system-design. Plain Nunjucks markup uses eleventy-nunjucks;
React and shadcn guidance applies only where those dependencies are present.

Installing these packages does not configure MCP servers, add application
components, enable hooks or authorize dependency changes. Preserve all supporting
rules, assets and scripts; load references on demand. vercel-react-best-practices
remains a future-review candidate, not an installed owner.
