#!/usr/bin/env python3
"""Merge or check the saved Claude Code attribution and skill listing settings."""
import argparse
import json
import os
from pathlib import Path
import tempfile

KEYS = ("attribution", "includeCoAuthoredBy")
# Optional; merged per skill so a local choice for the same skill wins.
OVERRIDES = "skillOverrides"
OVERRIDE_VALUES = {"on", "name-only", "user-invocable-only", "off"}
ROOT = Path(os.environ.get("DOTFILES", Path(__file__).resolve().parents[1]))


def read(path):
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError("settings must be a JSON object")
    return data


def snapshot(path):
    data = read(path)
    if not set(KEYS) <= set(data) <= {*KEYS, OVERRIDES}:
        raise ValueError("snapshot must contain attribution, includeCoAuthoredBy and optional skillOverrides")
    section = data["attribution"]
    if not isinstance(section, dict) or not all(type(v) is str for v in section.values()):
        raise ValueError("attribution must map to strings")
    if type(data["includeCoAuthoredBy"]) is not bool:
        raise ValueError("includeCoAuthoredBy must be boolean")
    overrides = data.get(OVERRIDES, {})
    if not isinstance(overrides, dict) or not all(
            type(k) is str and v in OVERRIDE_VALUES for k, v in overrides.items()):
        raise ValueError("skillOverrides must map skill names to a listing mode")
    return data


def merged(live, saved):
    data = {**live, **{key: saved[key] for key in KEYS}}
    if OVERRIDES in saved:
        local = live.get(OVERRIDES, {})
        if not isinstance(local, dict):
            raise ValueError("live skillOverrides must be a JSON object")
        data[OVERRIDES] = {**saved[OVERRIDES], **local}
    return data


def write(path, data):
    # Preserve existing symlinks and avoid partially written configuration.
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if path.exists() and path.read_text() == content:
        return
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as f:
            temporary = Path(f.name)
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("restore", "check"))
    parser.add_argument("--snapshot", type=Path, default=ROOT / "config/claude/settings.json")
    parser.add_argument("--settings", type=Path, default=Path.home() / ".claude/settings.json")
    args = parser.parse_args()
    saved = snapshot(args.snapshot)
    live = read(args.settings) if args.settings.exists() else {}
    if args.action == "restore":
        # Claude Code owns the rest of this file; replace only the managed keys.
        write(args.settings, merged(live, saved))
    elif any(live.get(key) != saved[key] for key in KEYS):
        raise ValueError("live attribution differs from snapshot; run the platform restore command")
    elif not set(saved.get(OVERRIDES, {})) <= set(live.get(OVERRIDES) or {}):
        raise ValueError("live skillOverrides lack saved skills; run the platform restore command")
    print("Claude attribution and skill overrides: " + args.action + " OK")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        # Never print settings contents or parser excerpts.
        detail = "invalid JSON" if isinstance(error, json.JSONDecodeError) else str(error)
        raise SystemExit("Claude attribution: " + detail)
