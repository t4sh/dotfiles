"""Shared lock-key → installed skill directory name mapping."""

import re
from pathlib import Path


def slugify(value):
    """Lock/display name → installed skill directory slug."""
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-")


def installed_name(key, skills_dir):
    """Return the name used by the installed skill directory and skills CLI."""
    slug = slugify(key)
    if (skills_dir / slug / "SKILL.md").exists():
        return slug
    # Backward-compatible fallback for unusual lock keys where the installed
    # directory genuinely keeps spaces/case.
    return key if key == key.lower().replace(" ", "-") else key.lower().replace(" ", "-")
