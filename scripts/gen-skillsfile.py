#!/usr/bin/env python3
"""
gen-skillsfile.py — regenerate ./Skillsfile from agents/.skill-lock.json.

Brewfile pattern:  this script is the `brew bundle dump`; `make skills` is
the `brew bundle`. Skillsfile is GENERATED — never hand-edit; change skills
with `npx skills add/remove` then re-run this.

GitHub-sourced skills are grouped by repo into one `npx skills add` line
each (with --skill <comma-list>). `local` skills are repo-native (vendored
in agents/skills/, no upstream) and listed as comments only.
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone, timedelta

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
BASE_DIR = os.path.join(REPO_ROOT, "agents")
LOCK_FILE = os.path.join(BASE_DIR, ".skill-lock.json")
SKILLSFILE = os.path.join(REPO_ROOT, "Skillsfile")
IST = timezone(timedelta(hours=5, minutes=30))
GENERATED_RE = re.compile(r"^# GENERATED (?P<stamp>.+) from agents/\.skill-lock\.json by$", re.M)


def norm(key):
    """Lock key → installed skill name (matches compareskills.py)."""
    return key if key == key.lower().replace(" ", "-") else key.lower().replace(" ", "-")


def existing_timestamp():
    try:
        text = open(SKILLSFILE).read()
    except FileNotFoundError:
        return None
    match = GENERATED_RE.search(text)
    return match.group("stamp") if match else None


def build_skillsfile(timestamp):
    with open(LOCK_FILE) as f:
        data = json.load(f)

    by_source = defaultdict(list)   # source repo -> [skill names]
    local = []
    for key, meta in data.get("skills", {}).items():
        name = norm(key)
        if meta.get("sourceType") == "github":
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
        "#   npx skills add/remove ...   then   make skills-manifest",
        "#",
        f"# Install everything:  make skills   (or: bash Skillsfile)",
        f"# {total} skills — {len(by_source)} github sources + {len(local)} local.",
        "#",
        "# Prereqs (fresh Mac): node + git + network access must be set up first.",
        "",
        "set -euo pipefail",
        "",
        'command -v npx >/dev/null || { echo "npx not found — set up node first" >&2; exit 1; }',
        "",
    ]

    for src in sorted(by_source):
        skills = ",".join(sorted(by_source[src]))
        lines.append(f'echo "→ {src}"')
        lines.append(f'npx skills add {src} --skill {skills} -g -y')
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

    timestamp = existing_timestamp() if args.check else None
    if timestamp is None:
        timestamp = datetime.now(IST).strftime("%Y-%m-%dT%H:%M:%S+05:30")

    content, total, github_sources, local_count = build_skillsfile(timestamp)

    if args.check:
        try:
            current = open(SKILLSFILE).read()
        except FileNotFoundError:
            print(f"Skillsfile missing: {SKILLSFILE}", file=sys.stderr)
            return 1
        if current != content:
            print("Skillsfile is out of sync. Run: make skills-manifest", file=sys.stderr)
            return 1
        print(f"Skillsfile is in sync ({total} skills — {github_sources} github sources, {local_count} local)")
        return 0

    with open(SKILLSFILE, "w") as f:
        f.write(content)
    os.chmod(SKILLSFILE, 0o755)

    print(f"Wrote {SKILLSFILE}")
    print(f"  {total} skills — {github_sources} github sources, {local_count} local")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
