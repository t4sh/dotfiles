#!/usr/bin/env python3
"""Stabilize sanitized snapshots and optionally review a disposable backup stage."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import sys
from urllib.parse import unquote, urlsplit
from xml.parsers.expat import ExpatError

from backup_metadata import apply_file_metadata, fingerprint, replace_bytes
from lib.plist_drift import describe, load, normalize, same_value

MISSING = object()
INVALID_PLIST = (ValueError, plistlib.InvalidFileException, ExpatError)
# macOS stamps these on a file according to the app that wrote it. They are not
# settings, so a difference in them alone is not a change to review.
OS_ASSIGNED_XATTRS = frozenset({"com.apple.provenance", "com.apple.quarantine"})
POLICY_DOMAINS = {
    "macos/dock-backup.plist": "com.apple.dock",
    "macos/mouse.plist": "com.apple.AppleMultitouchMouse",
}


def keep_saved_bytes(candidate, saved):
    """Give an equivalent capture the saved bytes, keeping its own metadata."""
    data = saved.read_bytes()
    if candidate.read_bytes() != data:
        replace_bytes(candidate, data, candidate)


def keep_current(label):
    while True:
        answer = input(f"{label}\nKeep current? [Y/n]: ").strip().lower()
        if answer in ("", "y", "yes"):
            return True
        if answer in ("n", "no"):
            return False
        print("Enter y or n.")


def display(key, value):
    if value is MISSING:
        return "(absent)"
    if key == "persistent-apps" and isinstance(value, list):
        tiles = []
        for tile in value:
            location = tile.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")
            name = Path(unquote(urlsplit(location).path)).stem
            tiles.append(name or tile.get("tile-type", "other tile"))
        return " → ".join(tiles) or "(empty Dock)"
    if isinstance(value, bytes):
        return f"data ({len(value)} bytes)"
    return describe(value)


def select_value(label, key, old, new, old_view, new_view):
    """Merge dictionary settings. Arrays and encoded plist data are single choices."""
    if same_value(old_view, new_view):
        return new
    if all(value is MISSING or isinstance(value, dict) for value in (old, new)):
        before = {} if old is MISSING else old
        after = {} if new is MISSING else new
        left = {} if old_view is MISSING else old_view
        right = {} if new_view is MISSING else new_view
        if left or right:
            result = after.copy()
            for child in sorted(left.keys() | right.keys()):
                selected = select_value(f"{label}.{child}", child, before.get(child, MISSING),
                                        after.get(child, MISSING), left.get(child, MISSING),
                                        right.get(child, MISSING))
                if selected is MISSING:
                    result.pop(child, None)
                else:
                    result[child] = selected
            if not result and (old is MISSING or new is MISSING):
                return MISSING
            return result
    prompt = f"{label}\n  Saved: {display(key, old)}\n  Current: {display(key, new)}"
    return new if keep_current(prompt) else old


def pending_dock_order(indexed_dock, previous, current):
    """Recover just a reorder already copied into the working snapshot."""
    working = previous.get("persistent-apps")
    if not isinstance(working, list) or not same_value(current.get("persistent-apps"), working):
        return None
    indexed = plistlib.loads(indexed_dock.read_bytes()).get("persistent-apps")
    if not isinstance(indexed, list) or same_value(indexed, working):
        return None
    # Match complete tiles, including repeated spacers. Never replace tile
    # contents or unrelated local edits with an older version from Git.
    if sorted(map(plistlib.dumps, indexed)) == sorted(map(plistlib.dumps, working)):
        return indexed
    return None


def review_system(candidate, saved, relative, policy, indexed_dock=None, metadata_source=None):
    raw = candidate.read_bytes()
    current = plistlib.loads(raw)
    old_bytes = saved.read_bytes() if saved.is_file() else None
    metadata_source = (metadata_source or saved) if old_bytes is not None else candidate
    try:
        previous = plistlib.loads(old_bytes) if old_bytes is not None else {}
    except INVALID_PLIST:
        if not keep_current(f"{relative}: replace unreadable saved plist with the valid capture?"):
            replace_bytes(candidate, old_bytes, metadata_source)
        return
    if not isinstance(current, dict) or not isinstance(previous, dict):
        review_file(candidate, saved, relative, metadata_source)
        return
    if indexed_dock and relative == "macos/dock-backup.plist":
        order = pending_dock_order(indexed_dock, previous, current)
        if order is not None:
            print("The working snapshot already contains this Dock move. Saved shows the Git index order.")
            previous["persistent-apps"] = order
            fmt = plistlib.FMT_BINARY if old_bytes.startswith(b"bplist") else plistlib.FMT_XML
            old_bytes = plistlib.dumps(previous, fmt=fmt, sort_keys=False)
    # The scalar review already decided these values. Preserve the plist type.
    domain = POLICY_DOMAINS.get(relative)
    for name, setting in policy.items():
        owner, _, key = name.partition("/")
        if domain == owner and (key in current or key in previous):
            reference = current.get(key, previous.get(key))
            current[key] = bool(setting) if isinstance(reference, bool) else setting
    old_view, new_view = normalize(previous), normalize(current)
    selected = current.copy()
    for key in sorted(old_view.keys() | new_view.keys()):
        if domain and f"{domain}/{key}" in policy:
            continue
        value = select_value(f"{relative}: {key}", key, previous.get(key, MISSING),
                             current.get(key, MISSING), old_view.get(key, MISSING),
                             new_view.get(key, MISSING))
        if value is MISSING:
            selected.pop(key, None)
        else:
            selected[key] = value
    selected_bytes = raw
    if same_value(normalize(selected), old_view):
        if old_bytes is None:
            candidate.unlink()
            return
        selected_bytes = old_bytes
    elif not same_value(selected, plistlib.loads(raw)):
        fmt = plistlib.FMT_BINARY if raw.startswith(b"bplist") else plistlib.FMT_XML
        selected_bytes = plistlib.dumps(selected, fmt=fmt, sort_keys=False)

    if selected_bytes == raw:
        if metadata_source == candidate:
            return
        saved_meta = fingerprint(metadata_source)
        if saved_meta is None:
            raise ValueError(f"missing saved metadata for {relative}")
        current_meta = fingerprint(candidate)
        if all(current_meta.get(k) == saved_meta.get(k) for k in ("mode", "acl", "xattrs")):
            return
    replace_bytes(candidate, selected_bytes, metadata_source)


def review_file(candidate, saved, relative, metadata_source=None):
    metadata_source = metadata_source or saved
    before = saved.read_bytes() if saved.is_file() else None
    after = candidate.read_bytes() if candidate.is_file() else None
    if before == after:
        if before is None:
            return
        previous_metadata = fingerprint(metadata_source)
        current_metadata = fingerprint(candidate)
        if previous_metadata is None:
            raise ValueError(f"missing saved metadata for {relative}")
        restamped = any(previous_metadata["xattrs"].get(name) != current_metadata["xattrs"].get(name)
                        for name in OS_ASSIGNED_XATTRS)
        for metadata in (previous_metadata, current_metadata):
            metadata["xattrs"] = {name: value for name, value in metadata["xattrs"].items()
                                  if name not in OS_ASSIGNED_XATTRS}
        fields = [key for key in ("mode", "acl", "xattrs")
                  if previous_metadata.get(key) != current_metadata.get(key)]
        if not fields:
            if restamped and os.access(candidate, os.W_OK):
                # Keep the saved stamp where macOS lets it be set, so an unchanged
                # file is not republished for it. Otherwise the fresh stamp stays;
                # a read-only file is left alone rather than half restamped.
                try:
                    apply_file_metadata(metadata_source, candidate)
                except OSError:
                    pass
            return
        change = "changed " + ", ".join(fields)
    elif before is None:
        change = "new file"
    elif after is None:
        change = "removed file"
    else:
        change = f"{len(before)} → {len(after)} bytes"
        if candidate.suffix in (".plist", ".json"):
            try:
                old, new = ((load(saved), load(candidate)) if candidate.suffix == ".plist"
                            else (json.loads(before), json.loads(after)))
            except INVALID_PLIST:
                old = new = None  # JSONC and other opaque settings still get a file-level review.
            if isinstance(old, dict) and isinstance(new, dict):
                keys = sorted(k for k in old.keys() | new.keys() if not same_value(old.get(k, MISSING), new.get(k, MISSING)))
                change = ", ".join(keys[:12]) or change
                if len(keys) > 12:
                    change += f" (+{len(keys) - 12} more)"
    if keep_current(f"{relative}: {change}"):
        return
    if before is None:
        candidate.unlink()
    else:
        candidate.parent.mkdir(parents=True, exist_ok=True)
        replace_bytes(candidate, before, metadata_source)


def save_dock_layout(stage):
    dock = stage / "macos/dock-backup.plist"
    if not dock.is_file():
        return
    fallback = stage / "macos/dock-layout.plist"
    if fallback.is_symlink() or dock.is_symlink():
        raise ValueError("unexpected symlink in Dock snapshots")
    tiles = plistlib.loads(dock.read_bytes()).get("persistent-apps", [])
    if not isinstance(tiles, list) or not all(isinstance(tile, dict) for tile in tiles):
        raise ValueError("expected an ordered list of Dock tiles")
    # Keep only the reviewed tiles. Domain policy and machine-assigned tile IDs
    # have no role in rebuilding a layout.
    layout = [{key: value for key, value in tile.items() if key != "GUID"} for tile in tiles]
    payload = plistlib.dumps({"persistent-apps": layout})
    if not fallback.exists():
        fallback.write_bytes(payload)
    elif fallback.read_bytes() != payload:
        replace_bytes(fallback, payload, fallback)


def stabilize(stage: Path, previous: Path, review_macos: bool = False, indexed_dock=None, base=None) -> int:
    retained = 0
    policy_file = stage / "config/macos-preferences.json"
    policy = json.loads(policy_file.read_bytes())["values"] if review_macos and policy_file.exists() else {}
    for root in ("apps", "macos", "services"):
        for candidate in sorted((stage / root).rglob("*.plist")):
            relative = candidate.relative_to(stage)
            if relative == Path("macos/dock-layout.plist"):
                continue  # Derived after the Dock review.
            saved = previous / relative
            if candidate.is_symlink() or saved.is_symlink():
                raise ValueError(f"unexpected symlink in preference snapshots: {relative}")
            if review_macos and root == "macos":
                review_system(candidate, saved, str(relative), policy, indexed_dock, (base or previous) / relative)
                continue
            if saved.is_file():
                try:
                    prior = load(saved)
                except INVALID_PLIST:
                    continue  # A fresh, valid capture can repair an invalid prior plist.
                if same_value(load(candidate), prior):
                    keep_saved_bytes(candidate, saved)
                    retained += 1
    if review_macos:
        files = {Path("config/codex/config.toml")}
        for tree in (stage, previous):
            files.update(p.relative_to(tree) for p in (tree / "apps").rglob("*") if p.is_file())
        for relative in sorted(files):
            candidate, saved = stage / relative, previous / relative
            if candidate.is_symlink() or saved.is_symlink():
                raise ValueError(f"unexpected symlink in preference snapshots: {relative}")
            review_file(candidate, saved, relative, (base or previous) / relative)
    save_dock_layout(stage)
    return retained


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    parser.add_argument("previous", type=Path)
    parser.add_argument("--review-macos", action="store_true")
    parser.add_argument("--base", type=Path, help="original metadata before sanitizing the comparison copy")
    parser.add_argument("--indexed-dock", type=Path, help="Git index snapshot for pending Dock moves")
    args = parser.parse_args()
    stage, previous = args.stage.resolve(), args.previous.resolve()
    if stage == previous or not stage.is_dir() or not previous.is_dir():
        parser.error("expected separate existing stage and previous directories")
    if args.review_macos and not sys.stdin.isatty():
        parser.error("preference review requires an interactive terminal")
    retained = stabilize(stage, previous, args.review_macos, args.indexed_dock, args.base)
    print(f"  retained {retained} equivalent plist snapshot(s)")


if __name__ == "__main__":
    try:
        main()
    except (EOFError, KeyboardInterrupt):
        sys.exit("Preference review interrupted; no backup was published.")
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        sys.exit(f"Preference snapshot review failed: {error}")
