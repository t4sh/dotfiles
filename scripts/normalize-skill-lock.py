#!/usr/bin/env python3
"""Keep refresh timestamps only when an installed skill's metadata changes."""
import json
from pathlib import Path
import sys


def normalize(before_path, lock_path):
    before_bytes = before_path.read_bytes()
    current_bytes = lock_path.read_bytes()
    before = json.loads(before_bytes)
    current = json.loads(current_bytes)
    for name, entry in current["skills"].items():
        previous = before["skills"].get(name)
        if previous is not None and {
            k: v for k, v in entry.items() if k != "updatedAt"
        } == {k: v for k, v in previous.items() if k != "updatedAt"}:
            if "updatedAt" in previous:
                entry["updatedAt"] = previous["updatedAt"]
            else:
                entry.pop("updatedAt", None)
    # Preserve the exact original bytes when the entire refresh was a no-op.
    content = before_bytes if current == before else (
        json.dumps(current, indent=2, ensure_ascii=False) + "\n"
    ).encode("utf-8")
    if content != current_bytes:
        lock_path.write_bytes(content)


if __name__ == "__main__":
    normalize(Path(sys.argv[1]), Path(sys.argv[2]))
