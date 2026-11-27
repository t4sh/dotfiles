#!/usr/bin/env python3
"""Publish app backups with compare-before-claim recovery for concurrent saves."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile

from backup_metadata import (
    apply_directory_metadata,
    apply_directory_metadata_fd,
    copy_entry,
    directory_search_flag,
    fingerprint,
)
from backup_metadata import rename_noreplace as _rename_noreplace

JOURNAL = "journal.jsonl"
OBJECTS = "originals"
CLAIMS = "claims"
UNDO_CLAIMS = "undo-claims"
STAGED = "staged"
DIRECTORY_METADATA = "directory-metadata"
CAPTURE_DIRECTORIES = ".capture-directories.json"


class ParentMovedError(RuntimeError):
    """The held directory no longer has the path used to reach it."""


class ClaimChangedError(RuntimeError):
    """A claimed object changed while being returned to its original path."""


def identity(path: Path) -> dict[str, int] | None:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    return {"device": int(info.st_dev), "inode": int(info.st_ino)}


def is_directory(path: Path) -> bool:
    try:
        return stat.S_ISDIR(path.lstat().st_mode)
    except FileNotFoundError:
        return False


def path_exists(path: Path) -> bool:
    return path.exists() or path.is_symlink()


def ancestors(relative: str) -> list[str]:
    parts = relative.split("/")
    return ["/".join(parts[:index]) for index in range(1, len(parts))]


def claim_slot(root: Path, relative: str) -> Path:
    digest = hashlib.sha256(os.fsencode(relative)).hexdigest()
    return root / digest


def raise_walk_error(error: OSError) -> None:
    raise error


def record_directories(base: Path, destination: Path, targets: list[str]) -> None:
    """Record the source directories before the first snapshot copy."""
    root = destination.resolve(strict=True)
    identities = {"": identity(root)}
    sparse_parents = {}
    for target in targets:
        for name in ancestors(target):
            if name in sparse_parents:
                continue
            if any(ancestor in targets for ancestor in [name, *ancestors(name)]):
                continue  # Covered by another full directory target.
            path = root / name
            parent_id = identity(path)
            metadata = fingerprint(path)
            if metadata is None or metadata["kind"] != "directory":
                raise RuntimeError(f"managed target traverses a non-directory parent: {name}")
            # Read the identity again so the metadata cannot belong to a replacement.
            if parent_id is None or parent_id != identity(path):
                raise ParentMovedError(f"structural directory changed during capture: {name}")
            identities[name] = parent_id
            sparse_parents[name] = metadata
        if is_directory(root / target):
            for path, _, _, fd in os.fwalk(root / target, onerror=raise_walk_error):
                info = os.fstat(fd)
                name = Path(path).relative_to(root).as_posix()
                identities[name] = {"device": info.st_dev, "inode": info.st_ino}
    # Exclusive creation prevents a retry from adopting a new owner mid-capture.
    with (base / CAPTURE_DIRECTORIES).open("x", encoding="utf-8") as stream:
        json.dump({"identities": identities, "sparse_parents": sparse_parents}, stream)


def inventory(root: Path, targets: list[str]) -> dict[str, dict[str, object]]:
    entries: dict[str, dict[str, object]] = {}
    for target in targets:
        root_path = root / target
        if not path_exists(root_path):
            raise RuntimeError(f"managed target missing from snapshot: {target}")
        entries[target] = fingerprint(root_path) or {"kind": "missing"}
        for parent in ancestors(target):
            parent_entry = fingerprint(root / parent)
            if parent_entry is not None and parent_entry["kind"] != "directory":
                raise RuntimeError(f"managed target traverses a non-directory parent: {parent}")
            if parent_entry is not None:
                entries[parent] = parent_entry
        if entries[target]["kind"] != "directory":
            continue
        for current, directories, files in os.walk(root_path, onerror=raise_walk_error, followlinks=False):
            current_path = Path(current)
            for name in list(directories):
                path = current_path / name
                relative_path = path.relative_to(root).as_posix()
                item = fingerprint(path)
                if item is None:
                    continue
                entries[relative_path] = item
                if item["kind"] != "directory":
                    directories.remove(name)
            for name in files:
                path = current_path / name
                relative_path = path.relative_to(root).as_posix()
                item = fingerprint(path)
                if item is not None:
                    entries[relative_path] = item
    return entries


def journal_append(path: Path, record: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as output:
        output.write(json.dumps(record, sort_keys=True) + "\n")
        output.flush()
        os.fsync(output.fileno())


def parent_identity(path: Path) -> dict[str, int] | None:
    """Identify the directory that holds path; the checkout may be a symlink."""
    try:
        info = path.parent.stat()
    except FileNotFoundError:
        return None
    return {"device": int(info.st_dev), "inode": int(info.st_ino)}


def directory_open_flags() -> int:
    """Open a directory for descriptor-relative lookup without requiring list access."""
    return directory_search_flag() | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)


def metadata_directory_open_flags() -> int:
    """Open an enumerable directory for fd-based metadata operations."""
    return os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)


@contextmanager
def opened_parent(destination: Path, accepted_parents: list | None = None,
                  expected_identity: dict[str, int] | None = None):
    """Hold and verify the named parent until its descriptor-relative operation ends."""
    try:
        fd = os.open(destination.parent, directory_open_flags())
    except FileNotFoundError:
        raise FileNotFoundError(errno.ENOENT, "parent directory was removed by another writer",
                                str(destination.parent)) from None
    try:
        info = os.fstat(fd)
        held = {"device": info.st_dev, "inode": info.st_ino}
        if expected_identity is not None and held != expected_identity:
            raise ParentMovedError(f"parent directory was replaced: {destination.parent}")
        if accepted_parents is not None and held not in accepted_parents:
            raise FileNotFoundError(errno.ENOENT, "parent directory was replaced by another writer",
                                    str(destination.parent))
        if parent_identity(destination) != held:
            raise ParentMovedError(f"parent directory moved while opening: {destination.parent}")
        yield fd
        if parent_identity(destination) != held:
            raise ParentMovedError(f"parent directory moved during filesystem operation: {destination.parent}")
    finally:
        os.close(fd)


def directory_entry_identity(parent_fd: int, name: str) -> dict[str, int] | None:
    try:
        info = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    return {"device": info.st_dev, "inode": info.st_ino}


def restore_entry_noreplace(source: Path, destination: Path, accepted_parents: list | None = None) -> None:
    """Install a saved file or a prepared, witnessed directory into its verified parent."""
    with opened_parent(destination, accepted_parents) as fd:
        if is_directory(source):
            _rename_noreplace(source, Path(destination.name), fd)
        else:
            os.link(source, destination.name, dst_dir_fd=fd, follow_symlinks=False)


def restore_claim_noreplace(source: Path, destination: Path, accepted_parents: list | None = None,
                            parent_fd: int | None = None) -> None:
    """Return a displaced entry, retaining the claim if the destination parent moves."""
    directory = is_directory(source)
    if parent_fd is None:
        restore_entry_noreplace(source, destination, accepted_parents)
    elif directory:
        _rename_noreplace(source, Path(destination.name), parent_fd)
    else:
        source_identity = identity(source)
        os.link(source, destination.name, dst_dir_fd=parent_fd, follow_symlinks=False)
        if identity(source) != source_identity:
            raise ClaimChangedError(f"claimed entry changed while being returned: {source}")
    if not directory:
        source.unlink()


def prepared_restore(rollback_root: Path, relative: str, source: Path, expected: dict) -> Path:
    """Persist the identity of our empty directory before exposing it to other writers."""
    prepared = claim_slot(rollback_root / "restore-directories", relative)
    prepared.parent.mkdir(parents=True, exist_ok=True)
    prepared.mkdir(mode=0o700, exist_ok=True)
    if not is_directory(prepared) or any(prepared.iterdir()):
        raise RuntimeError(f"unexpected contents in prepared restore directory: {prepared}")
    apply_directory_metadata(source, prepared)
    if fingerprint(prepared) != expected:
        raise RuntimeError(f"saved directory metadata changed: {relative}")
    witness = claim_slot(rollback_root / "directory-witnesses", relative)
    witness.parent.mkdir(parents=True, exist_ok=True)
    temporary = witness.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8") as output:
        json.dump(identity(prepared), output)
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, witness)
    # Persist the rename and the witness directory entry before installation.
    for directory in (witness.parent, rollback_root):
        fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    return prepared


def _copy_original(source: Path, destination: Path, before: dict[str, object] | None) -> None:
    if before is None:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    if path_exists(destination):
        if fingerprint(destination) == before:
            return
        if before["kind"] == "directory" and is_directory(destination):
            # Saving a nested directory first created this one with default
            # metadata; give it the metadata of the directory it stands for.
            apply_directory_metadata(source, destination)
            if fingerprint(destination) == before:
                return
        raise RuntimeError(f"recovery path already contains different data: {destination}")
    copy_entry(source, destination)
    if fingerprint(destination) != before:
        raise RuntimeError(f"could not preserve original metadata for {source}")


def _make_stage(
    source: Path, destination: Path, expected: dict[str, object]
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if path_exists(destination):
        raise RuntimeError(f"staging path already exists: {destination}")
    copy_entry(source, destination)
    if fingerprint(destination) != expected:
        raise RuntimeError(f"could not preserve staged metadata for {source}")


def _record(
    relative: str,
    operation: str,
    state: str,
    before: dict[str, object] | None,
    after: dict[str, object] | None,
    **extra: object,
) -> dict[str, object]:
    return {
        "path": relative,
        "operation": operation,
        "state": state,
        "before": before,
        "after": after,
        **extra,
    }


def require_directory_metadata_identity(record, target):
    directory_id = record.get("installed_identity")
    if directory_id is None:
        raise ValueError(f"directory metadata record lacks its installed identity: {target}")
    return directory_id


def update_directory_metadata(source, target, parent_fd, journal, record, current, desired):
    """Make each metadata syscall recoverable within the held directory."""
    directory_id = require_directory_metadata_identity(record, target)
    with tempfile.TemporaryDirectory(dir=journal.parent) as scratch:
        verified = Path(scratch) / "metadata"
        _make_stage(source, verified, desired)
        with opened_child_directory(parent_fd, target, directory_id) as directory_fd:
            def verify(expected):
                actual = fingerprint(target)
                if identity(target) != directory_id or directory_entry_identity(parent_fd, target.name) != directory_id:
                    raise ParentMovedError(f"directory moved during metadata update: {target}")
                if actual != expected:
                    raise RuntimeError(f"directory metadata changed at {target}")

            def checkpoint(before, after):
                journal_append(journal, {**record, "metadata_step": {"before": before, "after": after}})

            def apply_step(write, field, value, attribute=None):
                nonlocal current
                updated = current.copy()
                if attribute is not None:
                    attributes = updated["xattrs"] = current["xattrs"].copy()
                    if value is None:
                        attributes.pop(attribute, None)
                    else:
                        attributes[attribute] = value
                elif value is None:
                    updated.pop(field, None)
                else:
                    updated[field] = value
                if updated == current:
                    return
                # A crash before or after this one syscall leaves one of these
                # two states. Earlier states or unrelated edits do not qualify.
                verify(current)
                checkpoint(current, updated)
                try:
                    verify(current)
                except (OSError, RuntimeError):
                    # We know the write did not start. Do not adopt another
                    # writer's concurrent change even if it matches our intent.
                    checkpoint(current, current)
                    raise
                write()
                verify(updated)
                os.fsync(directory_fd)
                current = updated

            verify(current)
            apply_directory_metadata_fd(verified, directory_fd, apply_step=apply_step)
            verify(desired)


def _claim_current(
    source: Path, claimed: Path, expected: dict[str, object] | None,
    parent_fd: int, expected_directory: dict[str, int] | None,
) -> bool:
    """Move an entry aside atomically, then verify the object that won the race."""
    claimed.parent.mkdir(parents=True, exist_ok=True)
    if path_exists(claimed):
        raise RuntimeError(f"claim path already exists: {claimed}")
    try:
        os.replace(source.name, claimed, src_dir_fd=parent_fd)
    except FileNotFoundError:
        return False
    actual = fingerprint(claimed)
    if actual == expected and (not is_directory(claimed) or (
        identity(claimed) == expected_directory and not any(claimed.iterdir())
    )):
        return True
    try:
        restore_claim_noreplace(claimed, source, parent_fd=parent_fd)
    except (OSError, ParentMovedError, ClaimChangedError):
        print(f"  ⚠ displaced concurrent entry retained at {claimed}", file=sys.stderr)
        return False
    return False


def count_changed_recovery_entries(entries) -> int:
    """Check named recovery copies for saves made through outstanding handles."""
    changed = 0
    for relative, saved, expected in entries:
        try:
            current = fingerprint(saved)
            altered = current is not None and (
                current != expected or (current["kind"] == "directory" and any(saved.iterdir()))
            )
        except OSError as error:
            print(f"  ⚠ could not inspect recovery copy for {relative} at {saved}: {error}", file=sys.stderr)
            changed += 1
            continue
        if altered:
            print(f"  ⚠ independent edit to {relative} retained at {saved}", file=sys.stderr)
            changed += 1
    return changed


def _publish_entry(
    baseline: dict[str, dict[str, object]],
    staged: dict[str, dict[str, object]],
    candidate: Path,
    rollback: Path,
    current_path: Path,
    relative: str,
    before: dict[str, object] | None,
    after: dict[str, object] | None,
    created_directories: set[str],
    displaced: dict[str, dict[str, object]],
    parent_identities: dict[str, dict[str, int]],
) -> bool:
    """Publish one path while reads, claims and installs share its held parent."""
    parent_relative = relative.rpartition("/")[0]
    with opened_parent(current_path, expected_identity=parent_identities[parent_relative]) as parent_fd:
        held_by = {"device": os.fstat(parent_fd).st_dev, "inode": os.fstat(parent_fd).st_ino}
        expected_parent = (
            staged.get(parent_relative) if parent_relative in created_directories
            else baseline.get(parent_relative)
        )
        actual_parent = fingerprint(current_path.parent)
        if expected_parent is not None and actual_parent != expected_parent:
            print(f"  ⚠ concurrent edit preserved: {relative}", file=sys.stderr)
            return True

        target = current_path
        if parent_identity(current_path) != {
            "device": os.fstat(parent_fd).st_dev, "inode": os.fstat(parent_fd).st_ino,
        } or fingerprint(target) != before:
            print(f"  ⚠ concurrent edit preserved: {relative}", file=sys.stderr)
            return True

        if after is not None and after["kind"] == "directory":
            if before is None:
                prepared_dir = claim_slot(rollback / "prepared-directories", relative)
                _make_stage(candidate / relative, prepared_dir, after)
                directory_id = identity(prepared_dir)
                journal_append(rollback / JOURNAL, _record(
                    relative, "directory-create", "intent", before, after,
                    installed_identity=directory_id, parent_identity=held_by,
                ))
                try:
                    _rename_noreplace(prepared_dir, Path(target.name), parent_fd)
                except FileExistsError:
                    print(f"  ⚠ concurrent edit preserved: {relative}", file=sys.stderr)
                    journal_append(rollback / JOURNAL, _record(
                        relative, "directory-create", "unresolved", before, after,
                        parent_identity=held_by,
                    ))
                    return True
                journal_append(rollback / JOURNAL, _record(
                    relative, "directory-create", "applied", before, after,
                    installed_identity=directory_id, parent_identity=held_by,
                ))
                created_directories.add(relative)
                parent_identities[relative] = directory_id
            else:
                original = rollback / DIRECTORY_METADATA / relative
                _copy_original(target, original, before)
                identity_before = parent_identities.get(relative)
                record = _record(relative, "directory-metadata", "intent", before, after,
                                 installed_identity=identity_before, parent_identity=held_by)
                update_directory_metadata(candidate / relative, target, parent_fd, rollback / JOURNAL,
                                          record, before, after)
                journal_append(rollback / JOURNAL, {**record, "state": "applied"})
                created_directories.add(relative)
                parent_identities[relative] = identity_before
            return False

        original_copy = (
            rollback / DIRECTORY_METADATA / relative
            if before is not None and before["kind"] == "directory"
            else rollback / OBJECTS / relative
        )
        _copy_original(target, original_copy, before)
        operation = "write" if after is not None else "delete"
        install_witness = rollback / STAGED / relative if after is not None else None
        if install_witness is not None:
            _make_stage(candidate / relative, install_witness, after)
        witness_identity = identity(install_witness) if install_witness is not None else None
        journal_append(rollback / JOURNAL, _record(
            relative, operation, "intent", before, after, parent_identity=held_by,
            install_witness=relative if install_witness is not None else None,
            witness_identity=witness_identity,
        ))

        claimed_path = claim_slot(rollback / CLAIMS, relative)
        if before is not None:
            if not _claim_current(target, claimed_path, before, parent_fd, parent_identities.get(relative)):
                print(f"  ⚠ concurrent edit preserved: {relative}", file=sys.stderr)
                journal_append(rollback / JOURNAL, _record(
                    relative, operation, "unresolved", before, after,
                    parent_identity=held_by,
                ))
                return True
            displaced[relative] = before

        if (after is None and before is not None and before["kind"] == "directory"
                and any(claimed_path.iterdir())):
            try:
                restore_claim_noreplace(claimed_path, target, parent_fd=parent_fd)
            except (OSError, ParentMovedError, ClaimChangedError):
                pass
            journal_append(rollback / JOURNAL, _record(
                relative, operation, "unresolved", before, after,
                parent_identity=held_by,
            ))
            print(f"  ⚠ concurrent directory contents preserved: {relative}", file=sys.stderr)
            return True

        if after is None:
            journal_append(rollback / JOURNAL, _record(
                relative, operation, "applied", before, after, parent_identity=held_by,
            ))
            print(f"  ✓ published deletion {relative}", flush=True)
            return False

        try:
            os.link(install_witness, target.name, dst_dir_fd=parent_fd, follow_symlinks=False)
        except FileExistsError:
            print(f"  ⚠ concurrent edit preserved: {relative}", file=sys.stderr)
            journal_append(rollback / JOURNAL, _record(
                relative, operation, "unresolved", before, after, parent_identity=held_by,
            ))
            return True
        journal_append(rollback / JOURNAL, _record(
            relative, operation, "applied", before, after, parent_identity=held_by,
            installed_identity=witness_identity, witness_identity=witness_identity,
        ))
        print(f"  ✓ published {relative}", flush=True)
        return False


@contextmanager
def opened_child_directory(parent_fd: int, destination: Path, expected_identity):
    """Open and hold the exact child directory while its metadata is updated."""
    fd = os.open(destination.name, metadata_directory_open_flags(), dir_fd=parent_fd)
    try:
        held = {"device": os.fstat(fd).st_dev, "inode": os.fstat(fd).st_ino}
        if held != expected_identity or directory_entry_identity(parent_fd, destination.name) != held:
            raise ParentMovedError(f"directory changed while opening metadata target: {destination}")
        yield fd
        if directory_entry_identity(parent_fd, destination.name) != held:
            raise ParentMovedError(f"directory moved during metadata update: {destination}")
    finally:
        os.close(fd)


def publish(
    base: Path, candidate: Path, destination: Path, rollback: Path, targets: list[str]
) -> int:
    base, candidate, destination, rollback = (
        path.resolve() for path in (base, candidate, destination, rollback)
    )
    journal = rollback / JOURNAL
    if path_exists(journal):
        raise RuntimeError(f"rollback journal already exists: {journal}")
    try:
        with (base / CAPTURE_DIRECTORIES).open(encoding="utf-8") as stream:
            capture = json.load(stream)
    except FileNotFoundError:
        raise RuntimeError("directory baseline missing; record directories before capturing snapshots") from None
    parent_identities = capture["identities"]
    if identity(destination) != parent_identities[""]:
        raise ParentMovedError(f"checkout directory changed during capture: {destination}")
    baseline = inventory(base, targets)
    staged = inventory(candidate, targets)
    # Only the files inside these structural parents are backed up. Scratch
    # mkdir permissions and inherited ACLs do not describe the source parent.
    for name, metadata in capture["sparse_parents"].items():
        for snapshot in (baseline, staged):
            if snapshot.get(name, {}).get("kind") != "directory":
                raise RuntimeError(f"missing structural directory in snapshot: {name}")
            snapshot[name] = metadata
    changed = {
        relative
        for relative in baseline.keys() | staged.keys()
        if baseline.get(relative) != staged.get(relative)
    }
    incompatible = [
        relative for relative in changed
        if baseline.get(relative) is not None and staged.get(relative) is not None
        and baseline[relative]["kind"] != staged[relative]["kind"]
    ]
    if incompatible:
        raise RuntimeError(
            "snapshot changes file types at unsupported paths: " + ", ".join(incompatible)
        )

    directories = [relative for relative in changed if staged.get(relative, {}).get("kind") == "directory"]
    writes = [
        relative for relative in changed
        if staged.get(relative, {}).get("kind") in {"file", "symlink"}
    ]
    deletes = [relative for relative in changed if relative not in directories and relative not in writes]
    ordered = (
        sorted(directories, key=lambda item: (item.count("/"), item))
        + sorted(writes)
        + sorted(deletes, key=lambda item: (-item.count("/"), item))
    )

    claims = rollback / CLAIMS
    conflicts = 0
    displaced = {}
    created_directories: set[str] = set()
    for relative in ordered:
        before = baseline.get(relative)
        after = staged.get(relative)
        current_path = destination / relative
        parent_conflict = False
        for parent in ancestors(relative):
            expected_parent = (
                staged.get(parent) if parent in created_directories
                else baseline.get(parent)
            )
            captured_id = parent_identities.get(parent)
            if (not expected_parent or expected_parent["kind"] != "directory"
                    or captured_id is None or identity(destination / parent) != captured_id):
                parent_conflict = True
                break
        # A directory present in just one of the identity and content baselines
        # arrived or disappeared while it was being captured.
        was_directory = before is not None and before["kind"] == "directory"
        changed_directory = (
            was_directory != (relative in parent_identities)
            or (was_directory and identity(current_path) != parent_identities[relative])
        )
        if parent_conflict or changed_directory:
            print(f"  ⚠ concurrent edit preserved: {relative}", file=sys.stderr)
            conflicts += 1
            continue
        try:
            if _publish_entry(
                baseline, staged, candidate, rollback, current_path, relative,
                before, after, created_directories, displaced, parent_identities,
            ):
                conflicts += 1
        except ParentMovedError as error:
            print(f"  ⚠ concurrent edit preserved: {relative} ({error})", file=sys.stderr)
            conflicts += 1

    conflicts += count_changed_recovery_entries(
        (path, claim_slot(claims, path), before) for path, before in displaced.items()
    )
    if conflicts:
        print(f"  ⚠ preserved {conflicts} path(s) changed during backup capture", file=sys.stderr)
        return 1
    return 0


def verified_original(copies, expected):
    """Find a recovery copy whose bytes and metadata match the journal."""
    for source in copies:
        try:
            if fingerprint(source) == expected:
                return source
        except OSError as error:
            print(f"  ⚠ could not verify {source}: {error}", file=sys.stderr)
    raise RuntimeError("no verified original remains")


def undo_install(target, claimed, original_copies, before, after, installed_identity, accepted_parents=None):
    """Finish undoing a proven installation, including a prior interrupted attempt."""
    current = fingerprint(target)
    resuming = path_exists(claimed)
    if not resuming:
        if current == before:
            return
        if current != after or identity(target) != installed_identity:
            raise RuntimeError("published entry disappeared or changed before rollback")

    # Keep the installed version available if neither original can be recovered.
    source = None
    if before is not None and current != before and (not resuming or current is None):
        source = verified_original(original_copies, before)
    if not resuming:
        claimed.parent.mkdir(parents=True, exist_ok=True)
        with opened_parent(target, accepted_parents) as fd:
            os.replace(target.name, claimed, src_dir_fd=fd)

    # An editor could have won the rename, or saved while rollback was stopped.
    # Check the actual displaced inode before returning it or restoring the original.
    if identity(claimed) != installed_identity or fingerprint(claimed) != after:
        if resuming:
            raise RuntimeError(f"unverified prior rollback claim retained at {claimed}")
        restore_claim_noreplace(claimed, target, accepted_parents)
        raise RuntimeError("concurrent entry preserved")
    if is_directory(claimed) and any(claimed.iterdir()):
        restore_claim_noreplace(claimed, target, accepted_parents)
        raise RuntimeError("independent directory contents preserved")

    current = fingerprint(target)
    if current != before:
        if current is not None or source is None:
            raise RuntimeError("concurrent edit preserved during rollback")
        restore_entry_noreplace(source, target, accepted_parents)
        if fingerprint(target) != before:
            raise RuntimeError("restored file changed during rollback")
    if is_directory(claimed):
        try:
            claimed.rmdir()
        except OSError:
            restore_claim_noreplace(claimed, target, accepted_parents)
            raise
    else:
        claimed.unlink()


def _settle_unresolved(relative, target, before, publish_claim, saved_original, holds_journaled_paths,
                       accepted_parents, rollback_root):
    """Return a conflicted path to its original once no other writer holds it.

    Returns None when the path is settled, otherwise the message that explains
    why it stays unresolved.
    """
    current = fingerprint(target)
    if current == before:
        return None
    if current is not None:
        return f"  ⚠ unresolved concurrent entry retained: {relative}"
    if fingerprint(publish_claim) == before:
        try:
            restore_claim_noreplace(publish_claim, target, accepted_parents)
        except OSError:
            # The original may already be back in place even though the claim
            # could not be removed afterwards.
            if fingerprint(target) != before:
                raise
        return None
    if (holds_journaled_paths and before.get("kind") == "directory"
            and fingerprint(saved_original) == before):
        # The directory vanished before it could be claimed. Paths journaled
        # under it return through their own records and need it back with its
        # saved metadata. With none, its removal by another writer stands.
        prepared = prepared_restore(rollback_root, relative, saved_original, before)
        restore_entry_noreplace(prepared, target, accepted_parents)
        return None
    return (f"  ⚠ unresolved: {relative} was removed by another writer; "
            f"its saved original is {saved_original}")


def undo_directory_metadata(target, rollback_root, saved, record, accepted_parents):
    directory_id = require_directory_metadata_identity(record, target)
    if identity(target) != directory_id:
        print(f"  ⚠ concurrent directory preserved: {record['path']}", file=sys.stderr)
        return 1
    before = record["before"]
    current = fingerprint(target)
    if current == before:
        return 0
    step = record.get("metadata_step")
    if step is None:
        # Legacy journal entries and finished publications have only the
        # complete before/after fingerprints.
        expected = (record["after"],)
    elif isinstance(step, dict) and set(step) == {"before", "after"}:
        expected = (step["before"], step["after"])
    else:
        raise ValueError("invalid directory metadata checkpoint")
    if current not in expected:
        print(f"  ⚠ concurrent directory metadata preserved: {record['path']}", file=sys.stderr)
        return 1
    with opened_parent(target, accepted_parents) as parent_fd:
        update_directory_metadata(saved, target, parent_fd, rollback_root / JOURNAL,
                                  {**record, "state": "restoring-metadata"}, current, before)
    return 0


def _undo_record(destination: Path, rollback_root: Path, relative: str, record: dict,
                 holds_journaled_paths: bool, accepted_parents: list | None = None) -> int:
    """Undo one journaled path and return the number of errors it leaves.

    accepted_parents lists the directory identities an original may be
    restored into; None, for a journal written before they were recorded,
    only requires a directory.
    """
    state = record.get("state")
    target = destination / relative
    operation = str(record.get("operation", ""))
    before = record.get("before")
    after = record.get("after")
    original = rollback_root / OBJECTS / relative
    directory_original = rollback_root / DIRECTORY_METADATA / relative
    claimed = claim_slot(rollback_root / UNDO_CLAIMS, relative)
    if state == "cancelled":
        if operation == "directory-create" and path_exists(claimed):
            print(f"  ⚠ legacy cancelled directory has an unresolved rollback claim: {claimed}", file=sys.stderr)
            return 1
        return 0
    valid_states = {"intent", "applied", "unresolved"}
    valid_operations = {"write", "delete", "directory-create", "directory-metadata"}
    restoring_metadata = state == "restoring-metadata" and operation == "directory-metadata"
    if ((state not in valid_states and not restoring_metadata) or operation not in valid_operations
            or "before" not in record or not (before is None or isinstance(before, dict))):
        print(
            f"  ⚠ unknown rollback record for {relative}; inspect {rollback_root} manually",
            file=sys.stderr,
        )
        return 1
    saved_original = directory_original if before and before.get("kind") == "directory" else original
    publish_claim = claim_slot(rollback_root / CLAIMS, relative)

    recorded_parent = record.get("parent_identity")
    if isinstance(recorded_parent, dict):
        parent_relative = relative.rpartition("/")[0]
        parent_path = destination / parent_relative if parent_relative else destination
        actual_parent_identity = identity(parent_path)
        acceptable_parents = accepted_parents or [recorded_parent]
        if actual_parent_identity not in acceptable_parents:
            reason = (
                "removed by another writer" if actual_parent_identity is None
                else "replaced by another writer"
            )
            print(
                f"  ⚠ parent directory was {reason} for {relative}; "
                f"inspect {rollback_root} and the moved directory manually",
                file=sys.stderr,
            )
            return 1

    if state == "unresolved":
        # Another writer held this path. It is settled once it matches the
        # original again; while it differs, both versions are kept.
        problem = _settle_unresolved(
            relative, target, before, publish_claim, saved_original, holds_journaled_paths,
            accepted_parents, rollback_root)
        if problem is None:
            return 0
        print(problem, file=sys.stderr)
        return 1

    if operation == "directory-metadata":
        return undo_directory_metadata(target, rollback_root, directory_original, record, accepted_parents)

    if state == "intent":
        if operation in {"write", "delete"}:
            current = fingerprint(target)
            if operation == "write" and (
                path_exists(claimed)
                or (current == after and identity(target) == record.get("witness_identity"))
            ):
                record["installed_identity"] = record.get("witness_identity")
                state = "applied"
            elif current == before:
                return 0
            else:
                # Stopped between claiming the original and recording the result:
                # a vacated path gets its claimed or saved original back.
                try:
                    problem = _settle_unresolved(
                        relative, target, before, publish_claim, saved_original, holds_journaled_paths,
                        accepted_parents, rollback_root)
                except OSError as error:
                    print(f"error: could not restore {relative}: {error}", file=sys.stderr)
                    return 1
                if problem is None:
                    return 0
                print(f"  ⚠ interrupted publication is uncertain: {relative}", file=sys.stderr)
                return 1
        elif operation == "directory-create":
            if not record.get("installed_identity"):
                print(f"  ⚠ interrupted directory creation is uncertain: {relative}", file=sys.stderr)
                return 1
            state = "applied"  # undo_install verifies the pre-recorded inode before removing it.

    if state != "applied":
        return 0

    if operation in {"write", "directory-create"}:
        if operation == "directory-create" and not path_exists(target) and not path_exists(claimed):
            prepared = claim_slot(rollback_root / "prepared-directories", relative)
            # A completed removal may precede its durable completion record.
            # A changed parent was rejected above. Its replacement cannot attest
            # to absence at the original location.
            if (identity(prepared) == record.get("installed_identity")
                    or (accepted_parents and parent_identity(target) in accepted_parents)):
                return 0
            print(
                f"  ⚠ installed directory is missing from its recorded parent: {relative}; "
                f"inspect {rollback_root} and moved directories manually",
                file=sys.stderr,
            )
            return 1
        try:
            undo_install(target, claimed, (original, publish_claim), before, after, record.get("installed_identity"),
                         accepted_parents)
        except (OSError, RuntimeError) as error:
            print(f"error: could not roll back {relative}: {error}", file=sys.stderr)
            return 1
        return 0

    # operation == "delete"
    if fingerprint(target) == before:
        return 0
    if path_exists(target):
        print(f"  ⚠ concurrent edit preserved during rollback: {relative}", file=sys.stderr)
        return 1
    try:
        if saved_original == directory_original:
            source = prepared_restore(rollback_root, relative, directory_original, before)
        else:
            source = verified_original((original, publish_claim), before)
        restore_entry_noreplace(source, target, accepted_parents)
        if fingerprint(target) != before:
            raise RuntimeError("restored entry changed during rollback")
    except OSError as error:
        print(f"error: could not restore {relative}: {error}", file=sys.stderr)
        return 1
    return 0


def rollback(destination: Path, rollback_root: Path) -> int:
    destination, rollback_root = destination.resolve(), rollback_root.resolve()
    journal = rollback_root / JOURNAL
    try:
        stream = journal.open("r+b")
    except FileNotFoundError:
        return 0
    with stream:
        # Manual recovery and trap-driven rollback share this inode. Keep it
        # locked through the final claim check, including across a waiting retry.
        fcntl.flock(stream, fcntl.LOCK_EX)
        return _rollback_locked(destination, rollback_root, stream)


def _rollback_locked(destination: Path, rollback_root: Path, stream) -> int:
    journal = rollback_root / JOURNAL
    latest: dict[str, dict[str, object]] = {}
    for line in stream:
        if not line.endswith(b"\n"):
            # A mutation starts only after its complete intent record is synced.
            # The last durable record and filesystem witnesses cover a torn append.
            stream.truncate(stream.tell() - len(line))
            os.fsync(stream.fileno())
            print("  ⚠ incomplete final journal entry; recovering from complete records", file=sys.stderr)
            break
        record = json.loads(line)
        latest[str(record["path"])] = record

    # Directories that other journaled paths live under.
    holding = {parent for path in latest for parent in ancestors(path)}
    errors = 0
    for relative, record in reversed(list(latest.items())):
        try:
            accepted = None
            if isinstance(record.get("parent_identity"), dict):
                accepted = [record["parent_identity"]]
                parent = relative.rpartition("/")[0]
                # Earlier post-install logs could record a competing inode.
                # Only a pre-install witness proves that we prepared this parent.
                witness = claim_slot(rollback_root / "directory-witnesses", parent)
                try:
                    accepted.append(json.loads(witness.read_text(encoding="utf-8")))
                except FileNotFoundError:
                    pass
            result = _undo_record(destination, rollback_root, relative, record, relative in holding,
                                  accepted)
        except (OSError, RuntimeError, ValueError) as error:
            # One path that cannot be read must not keep the others from returning.
            print(f"error: could not roll back {relative}: {error}", file=sys.stderr)
            errors += 1
            continue

        errors += result
        if result == 0 and record.get("state") != "cancelled":
            try:
                journal_append(journal, {**record, "state": "cancelled"})
            except OSError as error:
                print(f"error: could not record rollback progress for {relative}: {error}", file=sys.stderr)
                return 1

    # The original and the installed file may both have been open in an editor.
    # Check both after undoing every path, even on a retry with completed records.
    retained = []
    for path, record in latest.items():
        operation = record.get("operation")
        if operation in {"write", "delete"} and record.get("before") is not None:
            retained.append((path, claim_slot(rollback_root / CLAIMS, path), record["before"]))
        if operation == "write" and record.get("after") is not None:
            retained.append((path, rollback_root / STAGED / path, record["after"]))
    errors += count_changed_recovery_entries(retained)
    return 1 if errors else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("record-directories", "publish", "rollback"))
    parser.add_argument("--base", type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--rollback", type=Path)
    parser.add_argument("--target", action="append", default=[])
    args = parser.parse_args()

    try:
        if args.operation == "record-directories":
            if args.base is None or not args.target:
                parser.error("record-directories requires --base and at least one --target")
            record_directories(args.base, args.destination, args.target)
            return 0
        if args.rollback is None:
            parser.error(f"{args.operation} requires --rollback")
        if args.operation == "publish":
            if args.base is None or args.candidate is None or not args.target:
                parser.error("publish requires --base, --candidate and at least one --target")
            return publish(args.base, args.candidate, args.destination, args.rollback, args.target)
        return rollback(args.destination, args.rollback)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
