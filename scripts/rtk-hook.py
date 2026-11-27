#!/usr/bin/env python3
"""Merge or check the RTK PreToolUse hook for Codex or Claude Code on macOS."""
import argparse
import json
import os
from pathlib import Path
import shutil
import shlex
import tempfile

def read(path):
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError("settings must be a JSON object")
    hooks = data.get("hooks", {})
    if not isinstance(hooks, dict) or not isinstance(hooks.get("PreToolUse", []), list):
        raise ValueError("hooks.PreToolUse must be a JSON array")
    for group in hooks.get("PreToolUse", []):
        if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
            raise ValueError("each PreToolUse group must contain a hooks array")
    return data


def is_rtk(hook, client):
    try:
        words = shlex.split(str(hook.get("command", ""))) if isinstance(hook, dict) else []
    except ValueError:
        return False
    return len(words) == 3 and Path(words[0]).name == "rtk" and words[1:] == ["hook", client]


def rtk_hooks(data, client):
    return [(group, hook)
            for group in data.get("hooks", {}).get("PreToolUse", [])
            if isinstance(group, dict)
            for hook in group.get("hooks", []) if is_rtk(hook, client)]


def merge(data, command, client):
    # Drop every prior RTK entry, keep unrelated hooks, then add one canonical entry.
    groups = []
    for group in data.get("hooks", {}).get("PreToolUse", []):
        if isinstance(group, dict) and isinstance(group.get("hooks"), list):
            kept = [hook for hook in group["hooks"] if not is_rtk(hook, client)]
            if not kept:
                continue
            group = {**group, "hooks": kept}
        groups.append(group)
    entry = {"type": "command", "command": command}
    if client == "codex":
        entry["statusMessage"] = "RTK command compression"
    groups.append({"matcher": "Bash", "hooks": [entry]})
    hooks = {**data.get("hooks", {}), "PreToolUse": groups}
    return {**data, "hooks": hooks}


def write(path, data, detach=False):
    # Preserve existing symlinks and avoid partially written configuration.
    path = path.absolute() if detach else path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if path.exists() and path.read_text() == content and not (detach and path.is_symlink()):
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
    parser.add_argument("--client", choices=("claude", "codex"), default="claude")
    parser.add_argument("--settings", type=Path)
    parser.add_argument("--rtk", help="rtk executable (default: resolved from PATH)")
    args = parser.parse_args()
    if args.settings is None:
        args.settings = Path.home() / (".codex/hooks.json" if args.client == "codex" else ".claude/settings.json")
    rtk = args.rtk or shutil.which("rtk")
    if not rtk or not os.access(rtk, os.X_OK):
        raise ValueError("rtk executable not found; run make brew first")
    # Keep the stable PATH entry (e.g. /opt/homebrew/bin/rtk), not the versioned Cellar target.
    command = shlex.join([os.path.abspath(rtk), "hook", args.client])
    data = read(args.settings) if args.settings.exists() else {}
    if args.action == "restore":
        # Migrate only the previous dotfiles-owned Codex link into a local file.
        legacy = Path(__file__).resolve().parents[1] / "config/codex/hooks.json"
        detach = args.client == "codex" and args.settings.is_symlink() and args.settings.resolve() == legacy
        write(args.settings, merge(data, command, args.client), detach=detach)
    else:
        found = rtk_hooks(data, args.client)
        if len(found) != 1:
            raise ValueError(f"expected one RTK hook, found {len(found)}; run make restore-{args.client}-rtk")
        group, hook = found[0]
        if group.get("matcher") != "Bash" or hook.get("command") != command:
            raise ValueError(f"RTK hook drifted; run make restore-{args.client}-rtk")
        if args.client == "codex" and hook.get("statusMessage") != "RTK command compression":
            raise ValueError("RTK hook label drifted; run make restore-codex-rtk")
    print(f"{args.client} RTK hook: {args.action} OK")
    if args.action == "restore" and args.client == "codex":
        print("Reload Codex and review/trust RTK command compression in Hooks (CLI: /hooks).")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        # Never print settings contents or parser excerpts.
        detail = "invalid JSON" if isinstance(error, json.JSONDecodeError) else str(error)
        raise SystemExit("RTK hook: " + detail)
