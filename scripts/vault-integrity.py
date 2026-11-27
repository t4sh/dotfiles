#!/usr/bin/env python3
"""Content receipts and completion sidecars for the persistent Mac vault."""

import argparse
from datetime import datetime
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


def check_image(image, *, allow_portable=False):
    metadata = json.loads(image.with_suffix(".json").read_text())
    if not isinstance(metadata, dict):
        raise ValueError("invalid vault metadata")
    checksum = image.with_suffix(".sha256").read_text().strip()
    sha = digest(image)
    schemas = (1, 2) if allow_portable else (2,)
    if (metadata.get("schema") not in schemas or metadata.get("filename") != image.name
            or metadata.get("sha256") != sha
            or metadata.get("sizeBytes") != image.stat().st_size
            or checksum != f"{sha}  {image.name}"):
        raise ValueError("vault sidecars do not match the image; preserve it for recovery")
    return metadata


def snapshot_age_days(names, max_age_days, now=None):
    """Validate local-time snapshot names and return the effective age in days."""
    if max_age_days < 1:
        raise ValueError("maximum snapshot age must be positive")
    if not isinstance(names, list) or not names or any(
            not isinstance(name, str) or not STAMP.fullmatch(name) for name in names):
        raise ValueError("vault metadata has no valid snapshot inventory")
    dates = [datetime.strptime(name, "%Y%m%d-%H%M%S") for name in names]
    age = ((now or datetime.now()) - max(dates)).total_seconds() / 86400
    # Snapshot names use local time. UTC+14 to UTC-12 can shift it by 26 hours.
    if age < -(26 / 24):
        raise ValueError("vault snapshot timestamp is in the future")
    if age >= max_age_days + 1:
        raise ValueError(f"vault snapshot is {int(age)} days old (limit: {max_age_days})")
    return max(0, int(age))


def image_health(image, max_age_days):
    """Verify a closed image without decrypting or treating cloud cache as remote proof."""
    if max_age_days < 1:
        raise ValueError("maximum snapshot age must be positive")
    metadata = check_image(image, allow_portable=True)
    names = metadata.get("snapshots") if metadata["schema"] == 2 else [metadata.get("snapshot")]
    age_days = snapshot_age_days(names, max_age_days)
    print(f"published vault image checksum verified; newest snapshot {max(names)} "
          f"is {age_days} day(s) old (limit: {max_age_days})")
    print("This verifies the selected files only; off-device replication and decryption are not established.")


def prune_space(root, reserve_bytes, min_keep=2, keep=None):
    """Prune oldest verified rolling snapshots; never touch baselines.

    Call only on the disposable working image. The published image remains the
    rollback point if available space or any later verification is insufficient.
    """
    if reserve_bytes < 1 or min_keep < 1 or (keep is not None and keep < min_keep):
        raise ValueError("invalid space retention policy")
    items = verified_snapshots(root)
    original_count = len(items)
    floor = min(min_keep, len(items))
    while (shutil.disk_usage(root).free < reserve_bytes
           or (keep is not None and len(items) > keep)):
        if len(items) <= floor:
            raise ValueError("vault cannot preserve the required snapshots and free-space reserve; increase capacity")
        shutil.rmtree(items.pop())
    print(f"retained {len(items)} rolling snapshot(s), pruned {original_count - len(items)}; free-space reserve satisfied")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["record", "check", "check-all", "prune", "sidecars", "check-image", "image-health", "snapshot-age", "prune-space"])
    parser.add_argument("path", type=Path)
    parser.add_argument("--keep", type=int)
    parser.add_argument("--reserve-bytes", type=int)
    parser.add_argument("--min-keep", type=int, default=2)
    parser.add_argument("--snapshots", nargs="*", default=[])
    parser.add_argument("--baselines", nargs="*", default=[])
    parser.add_argument("--max-age-days", type=int, default=30)
    args = parser.parse_args()
    if args.command == "record":
        receipt = args.path / RECEIPT
        with receipt.open("x") as stream:
            json.dump({"schema": 1, "entries": inventory(args.path)}, stream)
        check(args.path)
    elif args.command == "check":
        check(args.path)
    elif args.command == "prune-space":
        if args.reserve_bytes is None:
            raise ValueError("prune-space requires --reserve-bytes")
        prune_space(args.path, args.reserve_bytes, args.min_keep, args.keep)
    elif args.command == "check-all":
        verified_snapshots(args.path)
    elif args.command == "prune":
        if args.keep is None or args.keep < 1:
            raise ValueError("prune requires --keep")
        items = verified_snapshots(args.path)
        for path in items[args.keep:]:
            shutil.rmtree(path)
    elif args.command == "sidecars":
        sidecars(args.path, args.snapshots, args.baselines)
    elif args.command == "image-health":
        image_health(args.path, args.max_age_days)
    elif args.command == "snapshot-age":
        print(snapshot_age_days([args.path.name], args.max_age_days))
    else:
        check_image(args.path)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as exc:
        raise SystemExit(f"vault integrity check failed: {exc}") from None
