#!/usr/bin/env python3
"""
gen-skillsfile.py — regenerate ./Skillsfile from agents/.skill-lock.json.

Brewfile pattern: this script generates the explicit upstream-update manifest.
The checked-in agents/skills tree is the reproducible restore source; `make
skills-update` is the network-mutating refresh. Skillsfile is GENERATED.

GitHub-sourced skills are grouped by repo into one skills add line each (with
--skill <comma-list>). `local` skills are repo-native (vendored in
agents/skills/, no upstream) and listed as comments only.
"""

import argparse
import json
import os
import re
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
IST = timezone(timedelta(hours=5, minutes=30))
GENERATED_RE = re.compile(r"^# GENERATED (?P<stamp>.+) from agents/\.skill-lock\.json by$", re.M)


def existing_timestamp():
    try:
        text = SKILLSFILE.read_text()
    except FileNotFoundError:
        return None
    match = GENERATED_RE.search(text)
    return match.group("stamp") if match else None


def build_skillsfile(timestamp):
    with LOCK_FILE.open() as f:
        data = json.load(f)

    by_source = defaultdict(list)   # source repo -> [skill names]
    local = []
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
            by_source[meta["source"]].append(name)
        else:
            local.append(name)

    total = sum(len(v) for v in by_source.values()) + len(local)

    lines = [
        "#!/usr/bin/env bash",
        "# Skillsfile — declarative global skill manifest (Brewfile pattern).",
        "#",
        f"# GENERATED {timestamp} from agents/.skill-lock.json by",
        "# scripts/gen-skillsfile.py — DO NOT EDIT BY HAND. To change skills:",
        "#   ~/.local/bin/npx-stable skills add/remove ...   then   make skills-manifest",
        "#   (regenerates Skillsfile + agents/skills/README.md)",
        "#",
        "# Explicit upstream refresh: make skills-update   (or: bash Skillsfile)",
        f"# {total} skills — {len(by_source)} github sources + {len(local)} local.",
        "#",
        "# Prereqs (fresh Mac): node + git + GitHub auth (SSH/gh) must be set",
        "# up first — GitHub-hosted skill sources need auth when the registry requires it.",
        "# Agents and MCP tooling use the stable npx shim from ~/.local/bin.",
        "",
        "set -euo pipefail",
        "",
        'NPX="${NPX:-$HOME/.local/bin/npx-stable}"',
        '[[ -x "$NPX" ]] || { echo "npx stable shim not found or not executable: $NPX" >&2; exit 1; }',
        "",
    ]

    for src in sorted(by_source):
        skills = ",".join(sorted(by_source[src]))
        lines.append(f'echo "→ update {src}"')
        lines.append(f'"$NPX" skills add {src} --skill {skills} -g -y')
        lines.append("")

    if local:
        lines.append("# Local / repo-native skills (vendored in agents/skills/,")
        lines.append("# no upstream — they ship with the dotfiles repo itself):")
        for n in sorted(local):
            lines.append(f"#   {n}")
        lines.append("")

    lines.append('echo "✓ Skillsfile applied"')
    lines.append("")

    return "\n".join(lines), total, len(by_source), len(local)


def main():
    parser = argparse.ArgumentParser(description="Regenerate or check ./Skillsfile")
    parser.add_argument("--check", action="store_true", help="fail if Skillsfile is out of sync")
    args = parser.parse_args()

    existing_stamp = existing_timestamp()
    timestamp = existing_stamp or datetime.now(IST).strftime("%Y-%m-%dT%H:%M:%S+05:30")
    content, total, github_sources, local_count = build_skillsfile(timestamp)

    try:
        current = SKILLSFILE.read_text()
    except FileNotFoundError:
        current = None

    if args.check:
        if current is None:
            print(f"Skillsfile missing: {SKILLSFILE}", file=sys.stderr)
            return 1
        if current != content:
            print("Skillsfile is out of sync. Run: make skills-manifest", file=sys.stderr)
            return 1
        print(f"Skillsfile is in sync ({total} skills — {github_sources} github sources, {local_count} local)")
        return 0

    if current == content:
        os.chmod(SKILLSFILE, 0o755)
        print(f"Unchanged {SKILLSFILE}")
        print(f"  {total} skills — {github_sources} github sources, {local_count} local")
        return 0

    timestamp = datetime.now(IST).strftime("%Y-%m-%dT%H:%M:%S+05:30")
    content, total, github_sources, local_count = build_skillsfile(timestamp)
    SKILLSFILE.write_text(content)
    os.chmod(SKILLSFILE, 0o755)

    print(f"Wrote {SKILLSFILE}")
    print(f"  {total} skills — {github_sources} github sources, {local_count} local")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
