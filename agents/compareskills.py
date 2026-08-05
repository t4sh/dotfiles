#!/usr/bin/env python3
"""
compareskills.py — Inventory agents/skills/ against .skill-lock.json
and regenerate agents/skills/README.md.

Usage:  python3 agents/compareskills.py
        make skills-manifest   (also runs this after gen-skillsfile.py)
"""

import json
import argparse
import re
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))
from skill_lock_names import installed_name

BASE_DIR = REPO_ROOT / "agents"
SKILLS_DIR = BASE_DIR / "skills"
LOCK_FILE = BASE_DIR / ".skill-lock.json"
README_FILE = SKILLS_DIR / "README.md"

IST = timezone(timedelta(hours=5, minutes=30))


def get_disk_skills():
    """Sorted list of skill directory names on disk."""
    return sorted(
        f.name for f in SKILLS_DIR.iterdir()
        if f.is_dir() and not f.name.startswith(".")
    )


def get_gitignored_skills():
    """Skill dir names excluded from the dotfiles git repo via .gitignore."""
    gitignore = REPO_ROOT / ".gitignore"
    gated = set()
    if not gitignore.exists():
        return gated
    with gitignore.open() as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"agents/skills/([^/]+)/?$", line)
            if m:
                gated.add(m.group(1))
    return gated


def get_lock_skills():
    """Parse lock file → (version, {dir_name: {source, sourceType, lock_key}})."""
    with LOCK_FILE.open() as f:
        data = json.load(f)

    version = data.get("version", 0)
    skills = {}

    for key, meta in data.get("skills", {}).items():
        dir_name = installed_name(key, SKILLS_DIR)
        skills[dir_name] = {
            "source": meta.get("source", "unknown"),
            "sourceType": meta.get("sourceType", "unknown"),
            "lock_key": key,
        }

    return version, skills


def parse_existing_remarks():
    """Extract remarks from the current README table (preserves manual annotations)."""
    remarks = {}
    if not README_FILE.exists():
        return remarks

    with README_FILE.open() as f:
        for line in f:
            m = re.match(r"\|\s*\d+\s*\|\s*(\S+)\s*\|[^|]*\|[^|]*\|\s*(.*?)\s*\|", line)
            if m:
                name, remark = m.group(1).strip(), m.group(2).strip()
                if remark and remark != "\u2014":
                    remarks[name] = remark
    return remarks


def build_readme(disk_skills, lock_version, lock_skills, remarks, gated):
    """Generate the full README.md content."""

    total = len(disk_skills)
    remote = sum(1 for s in disk_skills if s in lock_skills and lock_skills[s]["sourceType"] != "local")
    local = total - remote

    gated_on_disk = sorted(s for s in disk_skills if s in gated)

    on_disk_only = sorted(s for s in disk_skills if s not in lock_skills)
    in_lock_only = sorted(s for s in lock_skills if s not in set(disk_skills))

    rows = []
    for i, name in enumerate(disk_skills, 1):
        source = lock_skills[name]["source"] if name in lock_skills else "local"
        remark = remarks.get(name, "\u2014")
        rows.append(f"| {i} | {name} | {source} | `~/.agents/skills/{name}/` | {remark} |")

    groups = {}
    for name in disk_skills:
        src = lock_skills[name]["source"] if name in lock_skills else "local"
        groups.setdefault(src, []).append(name)
    by_source = "\n".join(
        f"- **{src}** ({len(lst)}): {', '.join(lst)}"
        for src, lst in sorted(groups.items(), key=lambda x: (-len(x[1]), x[0]))
    )

    lock_miss = ", ".join(in_lock_only) if in_lock_only else "none"
    disk_miss = ", ".join(on_disk_only) if on_disk_only else f"none (all {total} skills tracked)"

    if gated_on_disk:
        gated_summary = (
            f" — {len(gated_on_disk)} **gated** "
            f"(on disk, excluded from git — see below)"
        )
        gated_section = (
            "### Gated — on disk, excluded from git\n\n"
            "These load normally but are intentionally untracked in this repo: "
            "canonical/source lives in another repo, or they are "
            "license-restricted and kept out of the public split. Managed via "
            "`.gitignore` + `scripts/audit-skill-licenses.sh` — this list is "
            "derived from `.gitignore`, not hardcoded.\n\n"
            f"- **{len(gated_on_disk)}:** {', '.join(gated_on_disk)}\n\n---\n\n"
        )
    else:
        gated_summary = ""
        gated_section = ""

    now = datetime.now(IST).strftime("%Y-%m-%dT%H:%M:%S+05:30")

    return f"""---
generated: {now}
skills_count: {total}
gated_count: {len(gated_on_disk)}
lock_file: ../.skill-lock.json
lock_version: {lock_version}
---

# Usage

When this file is asked to be updated. Update the following
- the front-matter for `generated`, `skills_count`, `gated_count` and `lock_version` whatever has changed/updated
- the content after "# Skills Inventory \u2014 Generated <date>"
\t- Summary of skills count
\t- Table with `Skill Name`, `Source`, `Disk Location`, `Remark`
- Leave rest of the content under other headings untouched.

# Skills Inventory

> **{total} skills** installed \u2014 {remote} remote + {local} local{gated_summary}

| # | Skill Name | Source | Disk Location | Remark |
|---|-----------|--------|---------------|--------|
{chr(10).join(rows)}

---

### Lock File vs Disk

- **In lock file but missing from disk:** {lock_miss}
- **On disk but not in lock file:** {disk_miss}

---

{gated_section}### By Source

{by_source}


# Compatibility Note

This README.md is a conventional location for documenting skills collection, and is a personal tracker. It won't interfere with skill discovery or validation for the following reasons:

1. **The spec only cares about subdirectories** \u2014 each skill is defined as "a directory containing at minimum a `SKILL.md`." The system scans for subdirectories with `SKILL.md` files. A `README.md` at the root level (`~/.agents/skills/README.md`) is not inside any skill directory, so it won't be picked up or misinterpreted as a skill.

2. **No prohibited files** \u2014 neither the [Claude docs](https://claude.com/docs/skills/how-to) nor the [agentskills.io spec](https://agentskills.io/specification) mention any restrictions on files placed alongside skill folders. The spec explicitly shows `\u2514\u2500\u2500 ...  # Any additional files or directories` as valid.

3. **The `name` validation only applies inside `SKILL.md` frontmatter** \u2014 it must match its parent directory name. A `README.md` at the root has no frontmatter to conflict with.

4. **The validation tool (`skills-ref validate`) works per-skill** \u2014 it validates individual skill directories, not the parent folder.

# Help - List and Manage the skills

* View global skills: `~/.local/bin/npx-stable skills list -g`

* Clear globals if needed: `~/.local/bin/npx-stable skills remove --all -y -g`

* Refresh all: `~/.local/bin/npx-stable skills update`
"""


def main():
    parser = argparse.ArgumentParser(description="Generate or verify the vendored skill inventory")
    parser.add_argument("--check", action="store_true", help="fail on missing locked skills or inventory drift")
    args = parser.parse_args()

    disk_skills = get_disk_skills()
    lock_version, lock_skills = get_lock_skills()
    remarks = parse_existing_remarks()
    gated = get_gitignored_skills()

    on_disk_only = sorted(s for s in disk_skills if s not in lock_skills)
    in_lock_only = sorted(s for s in lock_skills if s not in set(disk_skills))
    matched = len([s for s in disk_skills if s in lock_skills])

    print(f"Skills inventory  (lock version {lock_version})")
    print(f"  Disk:    {len(disk_skills)} folders")
    print(f"  Lock:    {len(lock_skills)} entries")
    print(f"  Matched: {matched}")

    if on_disk_only:
        print(f"  On disk but NOT in lock: {', '.join(on_disk_only)}")
    if in_lock_only:
        print(f"  In lock but NOT on disk: {', '.join(in_lock_only)}")
    if not on_disk_only and not in_lock_only:
        print("  Lock file and disk are in perfect sync")

    gated_on_disk = sorted(s for s in disk_skills if s in gated)
    if gated_on_disk:
        print(f"  Gated (on disk, excluded from git): {', '.join(gated_on_disk)}")

    content = build_readme(disk_skills, lock_version, lock_skills, remarks, gated)
    current = README_FILE.read_text() if README_FILE.exists() else None
    def stable(text: str) -> str:
        return re.sub(
            r"^generated: .+$",
            "generated: <stable>",
            text,
            count=1,
            flags=re.MULTILINE,
        )

    inventory_matches = current is not None and stable(current) == stable(content)
    if args.check:
        failed = False
        if in_lock_only:
            print("  ERROR: locked skills are missing from disk", file=sys.stderr)
            failed = True
        if not inventory_matches:
            print("  ERROR: agents/skills/README.md is out of sync", file=sys.stderr)
            failed = True
        if failed:
            print("  Run: make skills-update", file=sys.stderr)
            return 1
        print(f"\n  Verified {matched} locked skills on disk and current inventory")
        return 0

    if inventory_matches:
        print(f"\n  Unchanged {README_FILE}")
        print(f"  {len(disk_skills)} skills total")
        return 0

    README_FILE.write_text(content)
    print(f"\n  Wrote {README_FILE}")
    print(f"  {len(disk_skills)} skills total")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
