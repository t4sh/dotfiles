#!/usr/bin/env python3
"""Read-only Zed dependency check; authentication and activation are separate."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys


def read_settings(path):
    tokens = r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/'
    text = re.sub(tokens, lambda m: m[0] if m[0].startswith('"') else " ",
                  path.read_text(encoding="utf-8-sig"))
    text = re.sub(r'"(?:\\.|[^"\\])*"|,\s*(?=[}\]])',
                  lambda m: m[0] if m[0].startswith('"') else "", text)
    return json.loads(text)


def managed_matches(expected, actual):
    if isinstance(expected, dict):
        return isinstance(actual, dict) and all(
            key in actual and managed_matches(value, actual[key])
            for key, value in expected.items())
    return expected == actual


def check(repo, settings_dir, extensions_dir, snapshot_only=False):
    expected = read_settings(repo / "apps/zed/settings.json")
    keymap = read_settings(repo / "apps/zed/keymap.json")
    if not isinstance(expected, dict) or not isinstance(keymap, list):
        raise ValueError("Zed settings must be an object and keymap must be an array")
    extensions = expected.get("auto_install_extensions", {})
    if not isinstance(extensions, dict) or any(
        not re.fullmatch(r"[a-z0-9-]+", name) or not isinstance(enabled, bool)
        for name, enabled in extensions.items()
    ):
        raise ValueError("Invalid auto_install_extensions declaration")
    if snapshot_only:
        return []
    problems = []
    if extensions.get("nginx") and not shutil.which("nginx-language-server"):
        problems.append("Missing nginx-language-server executable; run uv tool install nginx-language-server")
    if not managed_matches(expected, read_settings(settings_dir / "settings.json")):
        problems.append("Managed settings differ; review live changes before make restore-zed")
    if read_settings(settings_dir / "keymap.json") != keymap:
        problems.append("Keymap differs; review live changes before make restore-zed")
    # These are the bundled themes selected by this profile. Additional themes
    # must be present in the declared extension payload, not just in settings.
    themes = {"One Light", "One Dark"}
    for name, enabled in extensions.items():
        if not enabled:
            continue
        directory = extensions_dir / name
        if not (directory / "extension.toml").is_file():
            problems.append("Missing extension: " + name + "; launch Zed to install")
            continue
        for theme_file in (directory / "themes").glob("*.json"):
            themes.update(theme["name"] for theme in read_settings(theme_file).get("themes", []))
    theme = expected.get("theme", {})
    selected = [theme] if isinstance(theme, str) else [theme[k] for k in ("light", "dark") if k in theme]
    for name in selected:
        if name not in themes:
            problems.append("Missing selected theme resource: " + name)
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(os.environ.get("DOTFILES", Path(__file__).resolve().parents[1])))
    parser.add_argument("--settings-dir", type=Path, default=Path.home() / ".config/zed")
    parser.add_argument("--extensions-dir", type=Path, default=Path.home() / "Library/Application Support/Zed/extensions/installed")
    parser.add_argument("--snapshot-only", action="store_true")
    args = parser.parse_args()
    try:
        problems = check(args.repo, args.settings_dir, args.extensions_dir, args.snapshot_only)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("Zed check could not complete: " + str(error))
        return 1
    if problems:
        print("Zed setup incomplete:\n  - " + "\n  - ".join(problems))
        return 1
    print("Zed snapshots parse." if args.snapshot_only else
          "Zed managed settings, keymap, declared extensions and selected theme resources match.")
    print("Language-server activation, fonts and agent authentication require in-editor verification.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
