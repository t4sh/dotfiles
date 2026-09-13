#!/usr/bin/env python3
"""
gen-skillsfile.py — regenerate ./Skillsfile from agents/.skill-lock.json.

Brewfile pattern: this script generates the explicit upstream-update manifest.
The checked-in agents/skills tree is the reproducible restore source; `make
skills-update` is the network-mutating refresh. Skillsfile is GENERATED.

GitHub-sourced skills are grouped by repo into one skills add line each (with
space-separated names after `--skill`). `local` skills are repo-native (vendored in
agents/skills/, no upstream) and listed as comments only.
"""

import argparse
import json
import os
import re
import shlex
import sys
from collections import defaultdict
from datetime import datetime, timezone, timedelta
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from skill_lock_names import installed_name

REPO_ROOT = SCRIPT_DIR.parent
BASE_DIR = REPO_ROOT / "agents"
LOCK_FILE = BASE_DIR / ".skill-lock.json"
SKILLS_DIR = BASE_DIR / "skills"
SKILLSFILE = REPO_ROOT / "Skillsfile"
HOLDS_FILE = REPO_ROOT / "config" / "skills-refresh-holds.json"
IST = timezone(timedelta(hours=5, minutes=30))
GENERATED_RE = re.compile(r"^# GENERATED (?P<stamp>.+) from agents/\.skill-lock\.json by$", re.M)


def existing_timestamp():
    try:
        text = SKILLSFILE.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    match = GENERATED_RE.search(text)
    return match.group("stamp") if match else None


def build_skillsfile(timestamp):
    with LOCK_FILE.open(encoding="utf-8") as f:
        data = json.load(f)
    # Keep policy outside the installer-owned lockfile. Missing or stale policy
    # must stop refresh, never silently make a curated skill updateable.
    holds = json.loads(HOLDS_FILE.read_text(encoding="utf-8"))
    if not isinstance(holds, dict) or any(
        key not in data["skills"] or not isinstance(reason, str) or not reason.strip()
        for key, reason in holds.items()
    ):
        raise ValueError("Skill refresh holds require known lock keys and nonempty reasons")

    by_source = defaultdict(list)   # source repo -> [skill names]
    local = []
    held = []
    for key, meta in data.get("skills", {}).items():
        name = installed_name(key, SKILLS_DIR)
        if meta.get("sourceType") == "github":
            folder_hash = meta.get("skillFolderHash", "")
            if not re.fullmatch(r"[0-9a-f]{40}", folder_hash):
                raise ValueError(
                    f"github skill {key!r} lacks an exact 40-character upstream tree hash"
                )
            if not meta.get("source") or not meta.get("skillPath"):
                raise ValueError(f"github skill {key!r} lacks source or skillPath metadata")
            # The lock key is the CLI install selector. It may intentionally
            # contain spaces/case even though the installed folder is slugged.
            if key in holds:
                held.append((key, meta["source"], holds[key]))
            else:
                by_source[meta["source"]].append(key)
        else:
            local.append(name)

    total = sum(len(v) for v in by_source.values()) + len(local) + len(held)

    lines = [
        "#!/usr/bin/env bash",
        "# Skillsfile — declarative global skill manifest (Brewfile pattern).",
        "#",
        f"# GENERATED {timestamp} from agents/.skill-lock.json by",
        "# scripts/gen-skillsfile.py — DO NOT EDIT BY HAND. To change skills:",
        "#   ~/.local/bin/npx-stable skills add ... --agent codex   then   make skills-manifest",
        "#   (regenerates Skillsfile + agents/skills/README.md)",
        "#",
        "# Explicit upstream refresh: make skills-update   (or: bash Skillsfile)",
        f"# {total} skills — {len(by_source)} refreshable github sources + {len(local)} local + {len(held)} held.",
        "# Curated skills are held by config/skills-refresh-holds.json; review upstream changes manually.",
        "#",
        "# Prereqs (fresh Mac): node + git + GitHub auth (SSH/gh) must be set",
        "# up first if a configured upstream source requires authentication.",
        "# Agents and MCP tooling use the stable npx shim from ~/.local/bin.",
        "# Target the canonical shared collection only; Hermes uses external_dirs, not installer aliases.",
        "",
        "set -euo pipefail",
        "",
        'DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"',
        '# Refuse stale generated selectors before any installer can overwrite skills.',
        '"${PYTHON_BIN:-python3}" "$DOTFILES_ROOT/scripts/gen-skillsfile.py" --check >/dev/null',
        "",
        'NPX="${NPX:-$HOME/.local/bin/npx-stable}"',
        '[[ -x "$NPX" || ( "${OS:-}" == "Windows_NT" && -f "$NPX" ) ]] || { echo "npx stable shim not found or not executable: $NPX" >&2; exit 1; }',
        "",
        '# skills add stamps unchanged entries too; normalize even after a partial failure.',
        'LOCK_SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/dotfiles-skills-lock.XXXXXXXXXX")"',
        'finish_refresh() {',
        '  status=$?',
        '  if ! "${PYTHON_BIN:-python3}" "$DOTFILES_ROOT/scripts/normalize-skill-lock.py" "$LOCK_SNAPSHOT" "$DOTFILES_ROOT/agents/.skill-lock.json"; then',
        '    printf "Normalization failed; pre-refresh lock retained at %s\\n" "$LOCK_SNAPSHOT" >&2',
        '    [[ "$status" -ne 0 ]] || status=1',
        '    exit "$status"',
        '  fi',
        '  rm -f -- "$LOCK_SNAPSHOT"',
        '  exit "$status"',
        '}',
        'cp -- "$DOTFILES_ROOT/agents/.skill-lock.json" "$LOCK_SNAPSHOT" || { status=$?; rm -f -- "$LOCK_SNAPSHOT"; exit "$status"; }',
        'trap finish_refresh EXIT',
        "",
        '# Keep installer banners/progress out of routine maintenance output.',
        'update_skill_source() {',
        '  local log status',
        '  log="$(mktemp "${TMPDIR:-/tmp}/dotfiles-skills.XXXXXXXXXX")"',
        '  if npm_config_yes=true "$@" >"$log" 2>&1; then',
        '    rm -f -- "$log"',
        '  else',
        '    status=$?',
        '    cat "$log" >&2',
        '    printf "Skills update failed (exit %s); log: %s\\n" "$status" "$log" >&2',
        '    return "$status"',
        '  fi',
        '}',
        "",
    ]

    for key, src, reason in sorted(held):
        message = f"HOLD: {src} / {key}: {reason}"
        lines.append(f"printf '%s\\n' {shlex.quote(message)}")
    lines.append("")

    for src in sorted(by_source):
        skills = " ".join(shlex.quote(name) for name in sorted(by_source[src]))
        lines.append(f'echo "Checking skills from source: {src}"')
        lines.append(f'update_skill_source "$NPX" skills add {src} --skill {skills} -g -y --agent codex')
        lines.append("")

    if local:
        lines.append("# Local / repo-native skills (vendored in agents/skills/,")
        lines.append("# no upstream — they ship with the dotfiles repo itself):")
        for n in sorted(local):
            lines.append(f"#   {n}")
        lines.append("")

    lines.append('echo "✓ Skillsfile applied"')
    lines.append("")

    return "\n".join(lines), total, len(by_source), len(local), len(held)


def main():
    parser = argparse.ArgumentParser(description="Regenerate or check ./Skillsfile")
    parser.add_argument("--check", action="store_true", help="fail if Skillsfile is out of sync")
    args = parser.parse_args()

    existing_stamp = existing_timestamp()
    timestamp = existing_stamp or datetime.now(IST).strftime("%Y-%m-%dT%H:%M:%S+05:30")
    content, total, github_sources, local_count, held_count = build_skillsfile(timestamp)
    summary = f"{total} skills — {github_sources} refreshable github sources, {local_count} local, {held_count} held"

    try:
        current = SKILLSFILE.read_text(encoding="utf-8")
    except FileNotFoundError:
        current = None

    if args.check:
        if current is None:
            print(f"Skillsfile missing: {SKILLSFILE}", file=sys.stderr)
            return 1
        if current != content:
            print("Skillsfile is out of sync. Run: make skills-manifest", file=sys.stderr)
            return 1
        print(f"Skillsfile is in sync ({summary})")
        return 0

    if current == content:
        os.chmod(SKILLSFILE, 0o755)
        print(f"Unchanged {SKILLSFILE}")
        print(f"  {summary}")
        return 0

    timestamp = datetime.now(IST).strftime("%Y-%m-%dT%H:%M:%S+05:30")
    content, total, github_sources, local_count, held_count = build_skillsfile(timestamp)
    with SKILLSFILE.open("w", encoding="utf-8", newline="\n") as output:
        output.write(content)
    os.chmod(SKILLSFILE, 0o755)

    print(f"Wrote {SKILLSFILE}")
    print(f"  {summary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
