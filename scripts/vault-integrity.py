#!/usr/bin/env python3
"""Content receipts and completion sidecars for the persistent Mac vault."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

RECEIPT = ".dotfiles-snapshot.json"
STAMP = re.compile(r"\d{8}-\d{6}\Z")


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def inventory(root):
    entries = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if relative == RECEIPT:
            continue
        if path.is_symlink():
            raise ValueError("snapshot contains a symlink")
        if path.is_file():
            # Finder may add/update these while browsing a writable vault.
            # They are already excluded from source backup, not recovery data.
            if path.name == ".DS_Store":
                continue
            entries[relative] = digest(path)
        elif path.is_dir():
            entries[relative] = None
        else:
            raise ValueError("snapshot contains a special file")
    if not any(key.startswith("payload/secrets/") and value is not None
               for key, value in entries.items()):
        raise ValueError("canonical secrets payload is empty or missing")
    return entries


def check(root):
    receipt = json.loads((root / RECEIPT).read_text())
    expected = receipt.get("entries")
    if isinstance(expected, dict):
        expected = {key: value for key, value in expected.items()
                    if not (Path(key).name == ".DS_Store" and value is not None)}
    if receipt.get("schema") != 1 or expected != inventory(root):
        raise ValueError("snapshot content differs from its verification receipt")


def snapshots(root):
    return sorted((p for p in root.iterdir() if STAMP.fullmatch(p.name)), reverse=True)


def verified_snapshots(root):
    result = snapshots(root)
    baseline_root = root / "baselines"
    if baseline_root.is_symlink() or (baseline_root.exists() and not baseline_root.is_dir()):
        raise ValueError("invalid baseline directory")
    baselines = snapshots(baseline_root) if baseline_root.is_dir() else []
    for path in result + baselines:
        if path.is_symlink() or not path.is_dir():
            raise ValueError("invalid snapshot directory")
        check(path)
    return result


def sidecars(image, snapshot_names, baseline_names=None):
    sha = digest(image)
    metadata = {
        "schema": 2, "filename": image.name, "container": "UDRW",
        "filesystem": "APFS", "encryption": "AES-256",
        "snapshots": snapshot_names, "sizeBytes": image.stat().st_size,
        "baselines": baseline_names or [],
        "sha256": sha,
    }
    for suffix, text in [
        (".json", json.dumps(metadata, indent=2) + "\n"),
        (".sha256", f"{sha}  {image.name}\n"),
    ]:
        target = image.with_suffix(suffix)
        partial = target.with_name(target.name + ".partial")
        with partial.open("x") as stream:
            stream.write(text)
        partial.chmod(0o600)
        partial.replace(target)


def check_image(image):
    metadata = json.loads(image.with_suffix(".json").read_text())
    checksum = image.with_suffix(".sha256").read_text().strip()
    sha = digest(image)
    if (metadata.get("schema") != 2 or metadata.get("filename") != image.name
            or metadata.get("sha256") != sha
            or metadata.get("sizeBytes") != image.stat().st_size
            or checksum != f"{sha}  {image.name}"):
        raise ValueError("vault sidecars do not match the image; preserve it for recovery")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["record", "check", "check-all", "prune", "sidecars", "check-image"])
    parser.add_argument("path", type=Path)
    parser.add_argument("--keep", type=int, default=5)
    parser.add_argument("--snapshots", nargs="*", default=[])
    parser.add_argument("--baselines", nargs="*", default=[])
    args = parser.parse_args()
    if args.command == "record":
        receipt = args.path / RECEIPT
        with receipt.open("x") as stream:
            json.dump({"schema": 1, "entries": inventory(args.path)}, stream)
        check(args.path)
    elif args.command == "check":
        check(args.path)
    elif args.command in ("check-all", "prune"):
        items = verified_snapshots(args.path)
        if args.command == "prune":
            if args.keep < 1:
                raise ValueError("retention must be positive")
            for path in items[args.keep:]:
                shutil.rmtree(path)
    elif args.command == "sidecars":
        sidecars(args.path, args.snapshots, args.baselines)
    else:
        check_image(args.path)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as exc:
        raise SystemExit(f"vault integrity check failed: {exc}") from None
