#!/usr/bin/env python3
"""Capture and merge only Cursor CLI's two attribution preferences."""
import argparse
import json
import os
from pathlib import Path
import tempfile

KEYS = ("attributeCommitsToAgent", "attributePRsToAgent")
ROOT = Path(os.environ.get("DOTFILES", Path(__file__).resolve().parents[1]))


def read(path):
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError("config must be a JSON object")
    return data


def attribution(data):
    section = data.get("attribution", {})
    if not isinstance(section, dict):
        raise ValueError("attribution must be a JSON object")
    result = {}
    for key in KEYS:
        # Cursor defaults omitted flags to true.
        value = section.get(key, True)
        if type(value) is not bool:
            raise ValueError("attribution." + key + " must be boolean")
        result[key] = value
    return {"attribution": result}


def snapshot(path):
    data = read(path)
    if data != attribution(data):
        raise ValueError("snapshot must contain exactly the two attribution booleans")
    return data


def write(path, data):
    # Preserve existing symlinks and avoid partially written configuration.
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(data, indent=2) + "\n"
    if path.exists() and path.read_text() == content:
        return
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as f:
        temporary = Path(f.name)
        try:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("capture", "restore", "check", "audit"))
    parser.add_argument("--snapshot", type=Path, default=ROOT / "apps/cursor/cli-config.json")
    parser.add_argument("--live", type=Path, default=Path.home() / ".cursor/cli-config.json")
    args = parser.parse_args()
    if args.action == "capture":
        if not args.live.exists():
            print("Cursor CLI config unavailable; prior snapshot retained")
            return
        write(args.snapshot, attribution(read(args.live)))
    else:
        saved = snapshot(args.snapshot)
        if args.action == "restore":
            live = read(args.live) if args.live.exists() else {"version": 1}
            attribution(live)  # Reject malformed data before changing anything.
            live.setdefault("attribution", {}).update(saved["attribution"])
            write(args.live, live)
        elif args.action == "check":
            if attribution(read(args.live)) != saved:
                raise ValueError("live attribution differs from snapshot")
    print("Cursor CLI attribution: " + args.action + " OK")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        # Never print config contents or parser excerpts containing private data.
        detail = "invalid JSON" if isinstance(error, json.JSONDecodeError) else str(error)
        raise SystemExit("Cursor CLI attribution: " + detail)
