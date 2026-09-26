# Motion skill routing

Load this reference when animation or motion is the requested deliverable.

| Request | Primary owner |
| --- | --- |
| Polish motion in one component as part of broader UI detail work | `better-ui` |
| Design, implement, or debug production UI motion, gestures, drag, or springs | `ui-animation` |
| Reverse-engineer motion from a recording, fit curves, or name a described effect | `ui-animation` |
| Install a named portable CSS transition recipe or normalize motion to its token set | `transitions-dev` |
| Apply explicitly Apple/WWDC-style physical gestures, momentum, springs, or materials | `apple-design` |
| Discover where motion should exist and propose recipes without implementing | `find-animation-opportunities` |
| Review an existing motion diff or animation code against a strict bar | `review-animations` — explicit invocation only |
| Audit repository-wide motion and produce implementation plans | `improve-animations` |
| Create cinematic, scroll-driven, immersive motion | `top-design` |

Use `better-ui` for small polish within broader interface work and `ui-animation` when motion itself is the implementation task. `transitions-dev` owns its named recipes, not general motion. Use `apple-design` only for explicit Apple-style physical interaction.

`find-animation-opportunities` is read-only discovery. Do not use it to review or fix existing animations. Do not use a repository-wide auditor for one component, or cinematic direction for routine product interaction.
