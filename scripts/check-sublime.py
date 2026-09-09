#!/usr/bin/env python3
"""Read-only Sublime restore check; resource presence is not plugin execution."""

import argparse
import ast
import json
from pathlib import Path
import re
import sys
from zipfile import BadZipFile, ZipFile


def read_settings(path):
    # Preserve quoted strings while removing JSON comments and trailing commas.
    tokens = r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/'
    text = re.sub(tokens, lambda m: m[0] if m[0].startswith('"') else " ", path.read_text(encoding="utf-8-sig"))
    text = re.sub(r'"(?:\\.|[^"\\])*"|,\s*(?=[}\]])',
                  lambda m: m[0] if m[0].startswith('"') else "", text)
    return json.loads(text)


def check(data, bundled, repo):
    user = data / "Packages/User"
    problems = []
    prefs = read_settings(user / "Preferences.sublime-settings")
    control = read_settings(user / "Package Control.sublime-settings")
    declared = control["installed_packages"]
    ignored = set(prefs.get("ignored_packages", []))
    pending = control.get("in_process_packages", [])
    if pending:
        problems.append("Package Control still processing: " + ", ".join(pending))

    packages = set()
    resources = set()
    for directory in (bundled, data / "Installed Packages"):
        for archive in directory.glob("*.sublime-package"):
            if archive.stem in ignored:
                continue
            try:
                with ZipFile(archive) as package:
                    resources.update("Packages/" + archive.stem + "/" + name
                                     for name in package.namelist() if not name.endswith("/"))
                packages.add(archive.stem)
            except BadZipFile:
                problems.append("Invalid package archive: " + archive.name)
    for package in (data / "Packages").glob("*"):
        if package.is_dir() and package.name not in ignored:
            packages.add(package.name)
            resources.update("Packages/" + path.relative_to(data / "Packages").as_posix()
                             for path in package.rglob("*") if path.is_file())

    for name in sorted(set(declared) | {"Package Control", "Markdown"}):
        if name in ignored:
            problems.append("Declared package disabled: " + name)
        elif name not in packages:
            problems.append("Missing package: " + name)

    helper = user / "default_syntax.py"
    expected = repo / "apps/sublime-text/default_syntax.py"
    if not helper.is_file() or helper.read_bytes() != expected.read_bytes():
        problems.append("Syntax helper missing or differs from repo; run make restore-apps")
    if "User" in ignored:
        problems.append("User package disabled; syntax helper cannot load")
    tree = ast.parse(expected.read_text())
    syntax = next(ast.literal_eval(node.value) for node in tree.body
                  if isinstance(node, ast.Assign)
                  and any(isinstance(target, ast.Name) and target.id == "DEFAULT_SYNTAX"
                          for target in node.targets))

    selected = [("default syntax", syntax)]
    for key in ("theme", "color_scheme"):
        value = prefs.get(key)
        if value == "auto":
            selected.extend((variant, prefs[variant]) for variant in
                            ("light_" + key, "dark_" + key) if variant in prefs)
        elif value:
            selected.append((key, value))
    for label, value in selected:
        found = value in resources if value.startswith("Packages/") else any(
            resource.rsplit("/", 1)[-1] == value for resource in resources)
        if not found:
            problems.append("Missing " + label + " resource: " + value)
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=Path.home() / "Library/Application Support/Sublime Text")
    parser.add_argument("--bundled-dir", type=Path, default=Path("/Applications/Sublime Text.app/Contents/MacOS/Packages"))
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        problems = check(args.data_dir, args.bundled_dir, args.repo)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("Sublime check could not complete: " + str(error), file=sys.stderr)
        return 1
    if problems:
        print("Sublime setup incomplete:")
        for problem in problems:
            print("  - " + problem)
        return 1
    print("Sublime helper, declared packages and selected resources are present.")
    print("Runtime plugin loading and license activation still require verification in Sublime.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
