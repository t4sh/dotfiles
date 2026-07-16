---
name: code-review-nextjs
description: This skill should be used when the user asks to "review Next.js code", "review this Next.js pull request", "check my App Router changes", "audit a Next.js component", or evaluate Next.js code quality, accessibility, security, performance, routing, caching, or framework conventions.
version: 0.2.0
---

# Next.js Code Review

Review Next.js 16 code as a senior software architect. Prioritize verified, actionable defects in the requested diff over generic advice or whole-codebase linting.

## 1. Establish the review boundary

1. Read repository instructions before evaluating code.
2. Resolve the review range from the user, pull request, staged changes, commit range, or current branch comparison.
3. Focus on changed files and the smallest set of callers, consumers, layouts, styles, and contracts needed to understand their behavior.
4. Read the package manager lockfile, `package.json`, Next.js config, TypeScript config, lint config, and relevant test configuration.
5. Identify the installed Next.js and React versions. Check current official documentation for version-sensitive claims.

Do not turn a scoped review into a whole-codebase audit. Report pre-existing issues only when the reviewed change directly depends on or worsens them, and label that relationship clearly.

## 2. Verify with project-defined commands

- Detect the repository package manager and use it consistently.
- Prefer project scripts such as `check-types`, `lint`, `test`, and `build` over direct tool invocations.
- Run the narrowest meaningful checks first. Run a production build when reviewing routing, rendering boundaries, configuration, static generation, or compile-time behavior.
- Do not delete `.next`, `out`, caches, snapshots, or generated artifacts as a routine precondition for type-checking.
- Do not run fixers, formatters, codemods, dependency upgrades, or other mutating commands during a review.
- Attribute failures to the reviewed change, pre-existing state, or the environment before reporting them.
- Report exactly which checks passed, failed, or were skipped.

## 3. Apply the finding bar

Report a finding only when all of these are true:

1. The reviewed change introduces or exposes it.
2. A concrete execution path, framework contract, rendered state, or tool result supports it.
3. The impact is material to correctness, security, accessibility, performance, or maintainability.
4. The recommendation is specific and implementable.

Avoid style-only findings already enforced by automated tooling. Avoid speculative claims based only on component length, nested `div` count, inline functions, object literals, or personal abstraction preferences.

## 4. Review checklist

Apply only the sections relevant to the change.

### Next.js 16 and App Router

- Keep Server Components as the default. Require `'use client'` only for hooks, event handlers, browser APIs, or client-only dependencies.
- Prevent server-only modules, credentials, privileged data, and non-serializable values from crossing into Client Components.
- Validate pages, layouts, templates, Route Handlers, loading, error, not-found, metadata, route groups, parallel routes, and intercepting routes against App Router conventions.
- Verify current request APIs, caching, revalidation, dynamic rendering, Server Functions, Suspense, and streaming behavior against the installed Next.js version.
- Review `proxy.ts` for Next.js 16. Treat `middleware.ts` and the `middleware` export as deprecated unless an explicit runtime constraint justifies them.
- Check redirects, rewrites, locale handling, cookie mutation, matcher scope, and authorization boundaries in Proxy or Route Handlers.
- Check static versus dynamic rendering decisions and guard against accidental opt-outs from caching or static generation.

### Images, fonts, scripts, and bundles

- Use `next/image` with meaningful `alt`, explicit dimensions or `fill`, and accurate responsive `sizes`.
- Apply current Next.js 16 LCP guidance. Prefer `preload`, `loading="eager"`, or `fetchPriority="high"` when appropriate; do not recommend the deprecated `priority` prop.
- Use `next/font` and `next/script` where they provide measurable loading, privacy, or layout benefits.
- Identify unnecessary Client Component boundaries, browser-only dependencies in server code, and heavy libraries shipped on initial routes.
- Recommend lazy loading or dynamic imports only when the bundle or interaction path supports the tradeoff.
- Require a plausible render or profiling impact before recommending memoization.

### React and TypeScript

- Check hook dependencies, effect cleanup, stale closures, race conditions, state ownership, keys, and controlled versus uncontrolled behavior.
- Follow repository conventions for `type` versus `interface`, import ordering, component APIs, and file organization.
- Flag `any`, non-null assertions, suppression comments, unsafe casts, and duplicated types when they create concrete risk in changed code.
- Validate public component props and cross-boundary data shapes. Prefer specific types, discriminated unions, generics, or `unknown` with narrowing as appropriate.
- Check error handling where asynchronous, network, parsing, or third-party operations can fail.

### Accessibility and user experience

- Use semantic elements and native controls before ARIA.
- Verify accessible names, labels, alt text, heading order, landmarks, focus visibility, keyboard operation, and status announcements.
- Check color contrast against WCAG 2.2 AA and ensure color is not the only state indicator.
- Respect `prefers-reduced-motion`; ensure reduced motion removes or substantially reduces non-essential movement.
- For UI changes, inspect affected desktop and narrow layouts plus relevant hover, focus, active, disabled, loading, empty, and error states when feasible.
- Report broken flows from actual navigation and interaction evidence, not grep counts or DOM depth alone.

### Security and data handling

- Keep secrets out of client bundles and require `NEXT_PUBLIC_` only for intentionally public values.
- Validate and authorize untrusted inputs at the server boundary.
- Review Server Functions and Route Handlers for authentication, authorization, CSRF exposure, unsafe redirects, and excessive data return.
- Require sanitization or a trusted source for `dangerouslySetInnerHTML`; trace the data origin before assigning severity.
- Check remote image, content security, cookie, and header configuration when touched by the change.

### Maintainability and tests

- Check clarity, naming, cohesion, duplication, dead code introduced by the change, and alignment with existing primitives.
- Require tests for important logic, regression-prone behavior, and user-critical flows when the repository has an established testing pattern.
- Do not require `data-testid` when semantic queries are sufficient.
- Do not require new abstractions or shared type folders when local colocation is clearer and consistent with the project.

## 5. Severity

| Severity | Meaning |
|---|---|
| **CRITICAL** | Exploitable security flaw, data loss, broken primary behavior, or accessibility blocker. |
| **WARNING** | Likely bug, framework violation, meaningful regression risk, or significant maintainability issue. |
| **SUGGESTION** | Bounded improvement that is helpful but not required for correctness. |

Do not inflate severity for formatting, preference, or hypothetical future scale.

## 6. Report format

Lead with findings, ordered by severity:

```markdown
## Findings

### [WARNING] Short actionable title
`path/to/file.tsx:42`

Explain the concrete failure path and user or system impact.

Recommendation: describe the smallest appropriate fix.

## Assessment

- Scope: reviewed range or files
- Verification: commands and outcomes
- Residual gaps: checks or runtime states not verified
- Verdict: APPROVE | REQUEST CHANGES | NEEDS DISCUSSION
```

Include exact file and tight line references. Consolidate repeated instances of one root cause. Omit empty categories and generic praise. If no actionable findings exist, state that directly and list only meaningful residual risks or unrun checks.

Reference official sources when framework behavior or standards are central:

- Next.js documentation: <https://nextjs.org/docs>
- Next.js 16 upgrade guide: <https://nextjs.org/docs/app/guides/upgrading/version-16>
- WCAG 2.2 quick reference: <https://www.w3.org/WAI/WCAG22/quickref/>
