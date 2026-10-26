# Skill installation checks

`make skills` checks the vendored inventory, licenses, generated manifest and the
external resources listed in `config/skill-install-resources.json`. A matching
upstream folder hash does not prove that referenced files outside that folder or
runtime engines have been installed.

`make skills-runtime` also probes the exact Impeccable engine version named in the
skill's `scripts/VERSION` and checks Fluid Functionalism's local Playwright
package. It is offline and never installs or downloads anything.

## Impeccable engine

The engine is a per-machine cache, not a committed binary. On Mac, run
`make skills-engine` to install it and verify the exact version; repeat runs reuse
a working engine. The upstream launcher downloads the versioned platform asset,
verifies its SHA-256 checksum before execution, and caches it under
`~/.impeccable/bin/<version>/`. A failed setup returns nonzero with repair guidance.
`make skills-update`, `make all`, and full Mac bootstrap run this setup step.
`make skills-engine-check` and Mac doctor check readiness without downloading;
`make skills-runtime` additionally checks the other runtime dependencies.
Windows uses the existing `dot skill-engine -Apply`
and verification-only `dot skill-engine` workflow. Engine installation is separate
from refreshing SKILL.md and the lock record.

## Browser helpers

On Mac, `make skills-browser` installs Fluid Functionalism's declared
`scripts/package.json` dependencies locally through stable Node/npm, with lifecycle
scripts disabled and without generating a tracked lockfile. Mac full setup and
curated refresh run this command so a replaced skill folder is repaired.
`make skills-browser-check`, doctor and `make skills-runtime` verify that the
installed package actually loads its Chromium launcher, without launching a
browser or downloading anything. Its `node_modules` stays ignored and is not
part of the public projection. Actual audits additionally need installed Chrome
or a compatible Chromium (or `CHROME_PATH`), and a page URL; dependency readiness
alone does not prove a browser can launch. This installer does not download browsers.

Localhost Screenshots uses the target project's Playwright installation. Run its
helpers with cwd at that project and the stable Node executable; follow its pinned
Playwright version and browser setup instructions. The local loader fix is held
against refresh until upstream includes it. Tests prove lookup from an unrelated
project directory without launching a browser.

Python libraries, project frameworks, browser downloads and authenticated service
connections remain task-specific. Use the skill's isolated environment or the
host's bundled runtime where applicable; do not install Python packages globally
or treat missing optional credentials as a broken installation.

## Repository-level references

Six Anthropic skills link to `../../CONNECTORS.md`. The installed
`agents/CONNECTORS.md` combines the upstream engineering and design category
references with a routing introduction; it enables no integrations. Hallmark's
external docs, tokens and worked examples live under `agents/docs/` and
`agents/site/` so its original relative paths resolve. Two supplemental human-doc
links are corrected for this installed layout. Upstream revisions, origins,
checksums and assembly notes are in `config/skill-install-resources.json`.

Keep these supplemental resources when refreshing or projecting the corresponding
skills. Update their source records when their upstream content changes. A skill
installer that copies only the skill directory will not restore these resources.

Vercel Composition Patterns is held out of automated refresh in
`config/skills-refresh-holds.json`: the skills installer deliberately excludes
`metadata.json` when rebuilding its directory, while this repository keeps the
complete pinned resource set. Update that skill manually with its supplemental
resource checksums; retain the hold until refresh preserves the required file.

## Ownership

The shared tree is repository-managed. Personal orchestration preferences remain
outside this tree.

Aside's entry point is vendor-CLI-managed; its live guide comes from that CLI.
`code-review-nextjs` is locally authored. Codex system and plugin-cache skills are
owned by Codex/plugin updates and must not be overwritten with shared-tree copies.
The nested `creative/typographic-poster-design` skill is also locally authored;
inventory discovery includes nested tracked skills and excludes dependency trees.
