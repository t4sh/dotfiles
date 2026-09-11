#!/usr/bin/env python3
"""Manage column defaults without replacing other Finder view preferences."""
import argparse
import plistlib
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("apply", "check", "dry-run"))
    mode = parser.parse_args().mode
    wanted = {"ArrangeBy": "modd", "ShowPreview": True}
    if mode == "dry-run":
        print("  would set Finder column defaults: Date Modified sort, preview on")
        return 0

    exported = subprocess.run(
        ["defaults", "export", "com.apple.finder", "-"],
        check=True, capture_output=True,
    )
    preferences = plistlib.loads(exported.stdout)
    options = preferences.get("StandardViewOptions", {})
    columns = options.get("ColumnViewOptions", {})
    if mode == "check":
        failed = False
        for key, expected in wanted.items():
            actual = columns.get(key)
            matches = actual == expected
            print(f"  {'✓' if matches else '✗'} Finder ColumnViewOptions.{key}: "
                  f"expected {expected}, got {actual}")
            failed |= not matches
        return int(failed)

    columns.update(wanted)
    options["ColumnViewOptions"] = columns
    # Write only this dictionary through cfprefsd, preserving all other keys
    # and leaving per-folder .DS_Store settings (including Applications) alone.
    subprocess.run(
        ["defaults", "write", "com.apple.finder", "StandardViewOptions",
         plistlib.dumps(options).decode()],
        check=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
