# 23 — Verification before completion

Activate when code, config, automation, data transforms, or generated artifacts are changed.

- **Verify the behavior you touched.** Run the narrowest meaningful test, build, lint, typecheck, script, preview, or command that proves the requested change works.
- **Wait for observable conditions.** Synchronize on fresh readiness evidence with an operational timeout and actionable error. Use fixed sleeps only when elapsed time is the tested behavior or an external requirement; establish the trigger and timing basis first.
- **Prefer project-defined commands.** Use the repo's documented verification path first. Otherwise choose the smallest meaningful check within authorized scope, including temporary test artifacts, and say what it covers.
- **Use evidence to size verification.** Only apply time or attempt limits explicitly set by the user, or imposed by the actual tool or service. Keep operational timeouts for hung commands. Choose reruns from changed inputs, observed failures, and required checks; do not invent task-wide timers, test quotas, or budget ledgers.
- **Keep merge checks conditional.** Merge-time CI/CD emulation and fallback check selection follow [Merge verification](lifecycle/integration.md#merge-verification). Ordinary change verification does not authorize a full integration suite.
- **Do not claim unrun checks.** Report exactly what passed, failed, or was skipped. If a check could not run because of missing deps, network, credentials, time, or sandbox limits, say so plainly.
- **Investigate failures in scope.** If a verification command fails, determine whether the failure is caused by your change, pre-existing state, environment, or an unrelated area before reporting it.
- **Stop when acceptance is met.** Reuse passing evidence for unchanged inputs. Once required checks pass and concrete concerns are resolved, finish; further reviews, tests, reports, or process changes need a specific unresolved reason.
- **Keep evidence concise.** Summarize the important command names and outcomes; include raw output only when the specific lines explain the result.

## Evidence and test value

- **Reviews follow content.** Record scope, revision, and staged, unstaged, and relevant untracked changes. Reuse verdicts only for unchanged supporting inputs. After repairs, review affected scope and dependencies. Report incomplete reviews; saved status or model agreement is not proof.
- **Tests protect contracts.** Name the observable contract, credible regression, and coverage gap before adding a test. Prefer extending existing tests; avoid implementation mirrors, test-only production seams, and count targets. Exact-output tests are valid when the bytes are the contract.
- **Prove regressions when feasible.** A regression test should fail for the original defect in its own assertion and pass after repair. Collection, fixture, and environment failures are not regression proof. Rerun the original probe and relevant adjacent behavior; report unavailable proof explicitly.
- **Close against acceptance.** Report delivered criteria, evidence, remaining concerns, and unrun checks. Blocked work names the blocker, attempted checks, and next action. Keep small-task reports short.

## Cross-client continuity

For substantial work across phases, clients, or sessions, use one handoff in the existing project convention: deliverable/mode, scope, owner, decisions and rationale, acceptance criteria, artifact paths, evidence, unresolved work, and next action. Link artifacts. Include inspected revisions and relevant working-tree changes; revalidate changed inputs. Chat suffices for small work; create no parallel memory store or client-specific rule copies.

Capture verified lessons that prevent repeated friction through existing project memory and client learning policy. No lesson is a valid outcome; learning never authorizes governing-rule edits.
