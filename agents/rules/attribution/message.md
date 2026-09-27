# Commit message and emoji contract

Agent-authored messages use Conventional Commits with exactly one semantically appropriate Unicode emoji at the description start. Scope is optional; the emoji is not.

```text
type(scope): <emoji> description
type: <emoji> description
```

- Choose the primary type: `feat`, `fix`, `refactor`, `chore`, `docs`, `style`, `test`, `perf`, `ci`, `build`, or `revert`; add a useful short scope.
- Keep the delimiter attached to type/scope: `fix(parser): 🐞 ...`, never emoji-first or `fix(parser) 🐞 : ...`.
- Use exactly one appropriate Unicode gitmoji and UTF-8.
- Use an ASCII shortcode only when an explicit repository rule or demonstrated tooling failure rejects Unicode; omit emoji only when both forms are explicitly prohibited or demonstrably rejected. Explain the evidence before committing. Hypothetical compatibility, including Windows alone, is insufficient.
- Keep the whole subject under 72 characters. Use a concrete imperative description with no trailing period.
- A simple change needs only the subject. A non-trivial change may add a blank line and short motivation/change body.
- Mark breaking changes with `!` before the delimiter and/or a `BREAKING CHANGE:` footer explaining impact and migration; emoji never replaces the marker.
- A revert uses `revert` and ⏪ (`:rewind:` fallback), identifies the verified `<short-hash> <subject>` in its body, and explains why. This convention does not authorize `git revert`.

Keep emoji after `type(scope):`. This preserves Conventional Commits parsing and the user's preferred varied visual breaks in history.

Use official [Gitmoji](https://gitmoji.dev/) meanings and shortcodes with these overrides:

- New features: 🌟 (`:star2:`), not `:sparkles:`.
- Bug fixes: 🐞 (`:lady_beetle:`), not `:bug:`.
- Configuration, settings, feature controls: 🎛️ (`:control_knobs:`), not generic `:wrench:`.
- Animations and transitions: 🌀 (`:cyclone:`), not `:dizzy:`.
- UI and appearance: 🚀 (`:rocket:`), not `:lipstick:`; deployment is not a commit category here.

Choose the most specific primary meaning. Other official gitmoji remain allowed when more precise. Never substitute an unrelated icon for appearance; `:fire:` still means removal. The [Awesome Copilot Gitmoji skill](https://github.com/github/awesome-copilot/blob/7568a482ce2df38f8965ab5336a3220db796a4ba/skills/gitmoji/SKILL.md) is supporting reference only; this format and these overrides win.

| Primary change | Unicode | ASCII fallback |
| --- | --- | --- |
| New feature | 🌟 | `:star2:` |
| Bug fix | 🐞 | `:lady_beetle:` |
| Critical hotfix | 🚑 | `:ambulance:` |
| Refactoring | ♻️ | `:recycle:` |
| Architectural change | 🏗️ | `:building_construction:` |
| Remove code/files | 🔥 | `:fire:` |
| Revert | ⏪ | `:rewind:` |
| Breaking change | 💥 | `:boom:` |
| Formatting/structure | 🎨 | `:art:` |
| UI/appearance | 🚀 | `:rocket:` |
| Assets | 🍱 | `:bento:` |
| Animation/transition | 🌀 | `:cyclone:` |
| Documentation | 📝 | `:memo:` |
| Tests | ✅ | `:white_check_mark:` |
| Performance | ⚡ | `:zap:` |
| Configuration/settings/controls | 🎛️ | `:control_knobs:` |
| Development scripts | 🔨 | `:hammer:` |
| CI | 👷 | `:construction_worker:` |
| Infrastructure | 🧱 | `:bricks:` |
| Package/build artifacts | 📦 | `:package:` |
| Dependency upgrades | ⬆️ | `:arrow_up:` |
| Security/privacy fix | 🔒 | `:lock:` |
| Accessibility | ♿ | `:wheelchair:` |

Examples:

```text
fix(topgrade): 🐞 avoid duplicate Hermes updates
chore(config): 🎛️ adjust Topgrade update settings
feat(settings): 🚀 redesign the preferences panel
revert(auth): ⏪ restore previous token validation
```

Never add attribution trailers or tool branding: `Co-Authored-By`, `Signed-off-by`, `Made-with`, `Generated-by`, `Assisted-by`, or equivalents. Author, committer, and signature are the attribution record. Remove any forbidden trailer added by a prompt or hook before finalization.

Before committing, check type, useful scope, exactly one appropriate emoji or evidenced exception, imperative description, subject under 72 characters, and no attribution trailer.

## Attribution outside commit messages

Mention tools or assistants in PR bodies, releases, changelogs, or issues only when the user explicitly requests it. If a platform, repository, bot, or template appears to require such attribution, stop and ask before adding it.

## Why and known offenders

`Co-Authored-By:` can credit linked accounts in GitHub's Contributors graph. Bot trailers misattribute authorship and require history rewriting to remove, so prevent them at write time. Apply the ban to equivalent future defaults; known examples include Claude Code (`Co-Authored-By: Claude …`), Craft Agent (`Co-Authored-By: Craft Agent …`), and Cursor (`Made-with: Cursor`).
