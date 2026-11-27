#!/usr/bin/env python3
"""Validate and restore Zed snapshots while retaining machine-local settings."""
import argparse
from contextlib import ExitStack
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import textwrap
from typing import NamedTuple, Optional

from backup_metadata import apply_file_metadata_fd, directory_search_flag, file_metadata_fd, rename_noreplace

JSONC_TOKENS = r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/'


def parse_jsonc(text):
    text = text.lstrip("\ufeff")
    text = re.sub(JSONC_TOKENS, lambda match: match[0] if match[0].startswith('"') else " ", text)
    text = re.sub(r'"(?:\\.|[^"\\])*"|,\s*(?=[}\]])',
                  lambda match: match[0] if match[0].startswith('"') else "", text)
    return json.loads(text)


def read_jsonc(path):
    return parse_jsonc(Path(path).read_text(encoding="utf-8-sig"))


def read_settings(path):
    value = read_jsonc(path)
    if not isinstance(value, dict):
        raise ValueError("Zed settings must be a JSON object")
    return value


LOCAL_SECTIONS = ("agent", "context_servers")
HOMEBREW_TOKEN = "__HOMEBREW_PREFIX__"


def parse_portable_settings(text):
    settings = parse_jsonc(text)
    if not isinstance(settings, dict):
        raise ValueError("Zed settings must be a JSON object")
    if any(key in settings for key in LOCAL_SECTIONS):
        raise ValueError("portable Zed snapshot contains a machine-local root section")
    return settings


def read_portable_settings(path):
    return parse_portable_settings(Path(path).read_text(encoding="utf-8-sig"))


def read_live_settings(live):
    """Return the live settings object; a missing, empty or comment-only file has none."""
    if not live or not Path(live).exists():
        return {}
    if not Path(live).is_file():
        raise ValueError(f"live Zed settings {live} is not a regular file")
    return parse_live_settings(Path(live).read_bytes(), live)


def parse_live_settings(data, live):
    try:
        text = data.decode("utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
        if not re.sub(JSONC_TOKENS, lambda match: match[0] if match[0].startswith('"') else " ", text).strip():
            return {}
        settings = parse_jsonc(text)
    except ValueError as error:
        raise ValueError(f"live Zed settings {live} cannot be parsed: {error}") from None
    if not isinstance(settings, dict):
        raise ValueError(f"live Zed settings {live} must be a JSON object")
    return settings


def merge_local_settings(original, local):
    result = parse_portable_settings(original)
    additions = [(key, local[key]) for key in LOCAL_SECTIONS if key in local]
    if not additions:
        return original
    masked = re.sub(JSONC_TOKENS, lambda match: match[0] if match[0].startswith('"') else
                    re.sub(r"[^\n]", " ", match[0]), original)
    opening = masked.find("{")
    if opening < 0:
        raise ValueError("Zed settings root object is missing")
    members = [textwrap.indent(
        json.dumps(key, ensure_ascii=False) + ": " +
        json.dumps(value, ensure_ascii=False, indent=2), "  ")
        for key, value in additions]
    content_start = opening + 1
    if original.startswith("\r\n", content_start):
        content_start += 2
        inserted = ",\n".join(members) + ("," if result else "") + "\r\n"
    elif original.startswith("\n", content_start):
        content_start += 1
        inserted = ",\n".join(members) + ("," if result else "") + "\n"
    else:
        inserted = "\n" + ",\n".join(members) + ("," if result else "") + "\n"
    merged = original[:content_start] + inserted + original[content_start:]
    parsed = parse_jsonc(merged)
    if not isinstance(parsed, dict) or any(parsed.get(key) != value for key, value in additions):
        raise ValueError("merged Zed settings failed validation")
    return merged


def preserve_local(snapshot, live):
    return merge_local_settings(Path(snapshot).read_bytes().decode("utf-8"), read_live_settings(live))


STAGING = ".dotfiles-zed-restore"
DARWIN_DELETE_OK = 1 << 12  # _DELETE_OK in Darwin's sys/unistd.h
FILE_FLAGS = os.O_NOFOLLOW | os.O_NONBLOCK if os.name == "posix" else 0


class FileState(NamedTuple):
    version: tuple
    data: bytes
    metadata: tuple


class RestoreFile(NamedTuple):
    destination: Path
    target: Path
    before: Optional[FileState]
    data: bytes
    mode: Optional[int]


def target_version(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid,
            getattr(info, "st_flags", 0), info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def read_slot(name, parent_fd=None, *, writable=False):
    """Read through a non-following handle and reject changes during the read."""
    try:
        existing = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(existing.st_mode):
        raise ValueError(f"{name} is not a regular file")
    flags = os.O_RDWR if writable else os.O_RDONLY
    try:
        fd = os.open(name, flags | FILE_FLAGS, dir_fd=parent_fd)
    except PermissionError as error:
        if writable:
            raise PermissionError(f"Zed restore destination is write-protected: {name}") from error
        raise
    with os.fdopen(fd, "rb") as source:
        version = target_version(existing)
        if version != target_version(os.fstat(fd)):
            raise ValueError(f"Zed restore destination changed: {name}")
        # A delete-denying ACL may let open succeed but forbid a rename.
        if writable and sys.platform == "darwin" and not os.access(
                name, DARWIN_DELETE_OK, dir_fd=parent_fd, follow_symlinks=False):
            raise PermissionError(f"Zed restore cannot replace {name}: delete access denied")
        data = source.read()
        metadata = file_metadata_fd(fd)
        if version != target_version(os.fstat(fd)):
            raise ValueError(f"Zed restore destination changed: {name}")
    return FileState(version, data, metadata)


def same_moved_file(expected, actual):
    # Rename changes ctime. Compare the inode, other stat fields, and the bytes.
    return (expected is not None and actual is not None
            and expected.version[:-1] == actual.version[:-1]
            and expected.data == actual.data and expected.metadata == actual.metadata)


def resolve_target(destination):
    try:
        return destination.resolve()
    except RuntimeError as error:
        raise ValueError(f"{destination} does not resolve to a regular file") from error


def check_outside_checkout(target, repo_info, destination):
    # Darwin can resolve differently cased path strings to the same directory.
    # Compare filesystem identity, including for existing ancestors of new files.
    for path in (target, *target.parents):
        try:
            if os.path.samestat(path.stat(), repo_info):
                raise ValueError(f"{destination} resolves inside the dotfiles checkout")
        except FileNotFoundError:
            continue


def inspect_target(destination, repo_info):
    """Resolve a live target and validate permissions without changing it."""
    target = resolve_target(destination)
    check_outside_checkout(target, repo_info, destination)
    try:
        (target.parent / STAGING).lstat()
    except FileNotFoundError:
        pass
    else:
        raise ValueError(f"restore in progress or recovery data remains at {target.parent / STAGING}")
    parent = next(path for path in target.parents if path.exists())
    if not parent.is_dir() or not os.access(parent, os.W_OK | os.X_OK):
        raise PermissionError(f"Zed restore directory is not writable: {parent}")
    existing = read_slot(target, writable=True)
    if existing is None and destination.is_symlink():
        raise ValueError(f"{destination} does not resolve to a regular file")
    return target, existing


def homebrew_prefix(snapshot):
    try:
        prefix = subprocess.check_output(["brew", "--prefix"], text=True, stderr=subprocess.DEVNULL).rstrip("\n")
    except (OSError, subprocess.CalledProcessError):
        prefix = ""
    if not prefix or not Path(prefix).is_dir():
        raise ValueError(f"Homebrew is required to materialize editor paths in {snapshot}")
    return prefix


def plan_restore(repo, settings_dir):
    plan = []
    seen = set()
    prefix = None
    repo_info = repo.stat()
    for name in ("settings.json", "keymap.json"):
        snapshot = repo / "apps/zed" / name
        if not snapshot.is_file():
            continue
        destination = settings_dir / name
        target, before = inspect_target(destination, repo_info)
        identity = before.version[:2] if before is not None else target
        if identity in seen:
            raise ValueError(f"Zed settings and keymap share a restore target: {target}")
        seen.add(identity)

        content = snapshot.read_bytes().decode("utf-8")
        mode = 0o600
        if HOMEBREW_TOKEN in content:
            if prefix is None:
                prefix = homebrew_prefix(snapshot)
            content = content.replace(HOMEBREW_TOKEN, prefix)
        elif name == "keymap.json":
            # Existing non-materialized keymaps keep the target's metadata,
            # as they did when the shell copied their bytes into place.
            mode = None if before is not None else stat.S_IMODE(snapshot.stat().st_mode)

        if name == "settings.json":
            try:
                local = parse_live_settings(before.data, target) if before is not None else {}
                content = merge_local_settings(content, local)
            except (OSError, ValueError) as error:
                raise ValueError(f"Zed settings cannot be merged: {error}") from None
        elif not isinstance(parse_jsonc(content), list):
            raise ValueError("Zed keymap must be a JSON array")
        plan.append(RestoreFile(destination, target, before, content.encode("utf-8"), mode))
    if not plan:
        raise ValueError("no Zed snapshot found")
    return plan


class RestoreDirectory(NamedTuple):
    path: Path
    live_fd: int
    stage_fd: int


@dataclass
class StagedFile:
    entry: RestoreFile
    directory: RestoreDirectory
    claimed: Optional[FileState] = None
    prepared: Optional[FileState] = None
    removed: Optional[FileState] = None

    @property
    def name(self):
        return self.entry.target.name

    @property
    def incoming(self):
        return "new-" + self.entry.destination.name

    @property
    def original(self):
        return "original-" + self.entry.destination.name

    @property
    def undone(self):
        return "undone-" + self.entry.destination.name


def open_target_parent(target, repo_info):
    """Walk the resolved parent by descriptor so a path swap cannot redirect writes."""
    flags = directory_search_flag() | os.O_DIRECTORY | os.O_NOFOLLOW
    parent = target.parent
    fd = os.open(parent.anchor, flags)
    try:
        for part in parent.parts[1:]:
            if os.path.samestat(os.fstat(fd), repo_info):
                raise ValueError(f"{target} resolves inside the dotfiles checkout")
            try:
                child = os.open(part, flags, dir_fd=fd)
            except FileNotFoundError:
                try:
                    os.mkdir(part, dir_fd=fd)
                except FileExistsError:
                    pass
                child = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = child
        if os.path.samestat(os.fstat(fd), repo_info):
            raise ValueError(f"{target} resolves inside the dotfiles checkout")
    except BaseException:
        os.close(fd)
        raise
    return fd


def verify_mapping(entry, parent_fd, repo_info):
    target = resolve_target(entry.destination)
    check_outside_checkout(target, repo_info, entry.destination)
    if target != entry.target or not os.path.samestat(target.parent.stat(), os.fstat(parent_fd)):
        raise ValueError(f"Zed restore destination or its directory changed: {entry.destination}")


def stage_bytes(item):
    entry = item.entry
    mode = entry.mode if entry.mode is not None else 0o600
    fd = os.open(item.incoming, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode,
                 dir_fd=item.directory.stage_fd)
    with os.fdopen(fd, "wb") as output:
        output.write(entry.data)
        output.flush()
        os.fsync(output.fileno())


def claim_original(item, repo_info):
    live, stage = item.directory.live_fd, item.directory.stage_fd
    verify_mapping(item.entry, live, repo_info)
    if read_slot(item.name, live, writable=True) != item.entry.before:
        raise ValueError(f"Zed restore destination changed: {item.entry.destination}")
    if item.entry.before is not None:
        rename_noreplace(item.name, item.original, stage, source_fd=live)
        # This is the entry the rename actually moved. A last-moment save
        # goes back through rollback, including a save using a different inode.
        item.claimed = read_slot(item.original, stage)
        if not same_moved_file(item.entry.before, item.claimed):
            raise ValueError(f"Zed restore destination changed during claim: {item.entry.destination}")


def prepare_install(item):
    stage = item.directory.stage_fd
    if item.entry.mode is None:
        # Copy the claimed keymap's metadata into the owned candidate. Both
        # handles are relative to staging, even if its parent has moved.
        with ExitStack() as descriptors:
            source = os.open(item.original, os.O_RDONLY | FILE_FLAGS, dir_fd=stage)
            descriptors.callback(os.close, source)
            output = os.open(item.incoming, os.O_WRONLY | FILE_FLAGS, dir_fd=stage)
            descriptors.callback(os.close, output)
            apply_file_metadata_fd(source, output)
            os.fsync(output)
    item.prepared = read_slot(item.incoming, stage)
    if item.prepared is None or item.prepared.data != item.entry.data:
        raise ValueError(f"staged Zed output changed: {item.entry.destination}")


def has_entry(name, directory_fd):
    try:
        os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    except FileNotFoundError:
        return False
    return True


def rollback_file(item):
    live, stage = item.directory.live_fd, item.directory.stage_fd
    if item.prepared is not None and not has_entry(item.incoming, stage):
        if not same_moved_file(item.prepared, read_slot(item.name, live)):
            raise ValueError("the installed entry changed during restore")
        rename_noreplace(item.name, item.undone, stage, source_fd=live)
        try:
            removed = read_slot(item.undone, stage)
            if not same_moved_file(item.prepared, removed):
                raise ValueError("an independent edit arrived during rollback")
        except (OSError, ValueError):
            # Return the actual entry we moved. If another file arrived since
            # then, keep both entries and report the staging path.
            rename_noreplace(item.undone, item.name, live, source_fd=stage)
            raise
        item.removed = removed
    if has_entry(item.original, stage):
        rename_noreplace(item.original, item.name, live, source_fd=stage)


def cleanup_restore(items, directories, complete):
    errors = []
    for item in items:
        stage = item.directory.stage_fd
        try:
            saved_name = item.original if complete else item.undone
            expected = item.claimed if complete else item.removed
            if expected is not None:
                if read_slot(saved_name, stage) != expected:
                    raise ValueError(f"an edit to {saved_name} was retained")
                os.unlink(saved_name, dir_fd=stage)
            if has_entry(item.incoming, stage):
                os.unlink(item.incoming, dir_fd=stage)
        except (OSError, ValueError) as error:
            errors.append(f"could not clean up {item.entry.destination}: {error}")
    for directory in directories:
        try:
            visible = os.stat(STAGING, dir_fd=directory.live_fd, follow_symlinks=False)
            if not os.path.samestat(visible, os.fstat(directory.stage_fd)):
                raise ValueError("staging directory moved")
            os.rmdir(STAGING, dir_fd=directory.live_fd)
        except (OSError, ValueError) as error:
            path = directory.path / STAGING
            if sys.platform == "darwin":
                import fcntl
                try:
                    actual = fcntl.fcntl(directory.stage_fd, fcntl.F_GETPATH, bytes(1024))
                    path = Path(os.fsdecode(actual.split(b"\0", 1)[0]))
                except OSError:
                    pass
            errors.append(f"inspect retained Zed restore data at {path}: {error}")
    return errors


def install_restore(plan, repo):
    repo_info = repo.stat()
    directories = {}
    staged = []
    complete = False
    with ExitStack() as descriptors:
        try:
            for entry in plan:
                live = open_target_parent(entry.target, repo_info)
                descriptors.callback(os.close, live)
                verify_mapping(entry, live, repo_info)
                info = os.fstat(live)
                identity = (info.st_dev, info.st_ino)
                if identity not in directories:
                    try:
                        os.mkdir(STAGING, 0o700, dir_fd=live)
                    except FileExistsError as error:
                        raise ValueError(f"restore in progress or recovery data remains at "
                                         f"{entry.target.parent / STAGING}") from error
                    try:
                        stage = os.open(STAGING, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=live)
                    except OSError:
                        os.rmdir(STAGING, dir_fd=live)
                        raise
                    descriptors.callback(os.close, stage)
                    directories[identity] = RestoreDirectory(entry.target.parent, live, stage)
                item = StagedFile(entry, directories[identity])
                staged.append(item)
                stage_bytes(item)

            # Acquire both originals before installing either output. This also
            # checks replacement rights at the point the kernel enforces them.
            for item in staged:
                claim_original(item, repo_info)
            for item in staged:
                prepare_install(item)
            for item in staged:
                live, stage = item.directory.live_fd, item.directory.stage_fd
                verify_mapping(item.entry, live, repo_info)
                try:
                    rename_noreplace(item.incoming, item.name, live, source_fd=stage)
                except FileExistsError as error:
                    raise ValueError(f"Zed restore destination changed during install: {item.entry.destination}") from error
            for item in staged:
                live, stage = item.directory.live_fd, item.directory.stage_fd
                verify_mapping(item.entry, live, repo_info)
                if (not same_moved_file(item.prepared, read_slot(item.name, live))
                        or (item.claimed is not None and read_slot(item.original, stage) != item.claimed)):
                    raise ValueError(f"Zed restore destination changed during install: {item.entry.destination}")
        except BaseException:
            for item in reversed(staged):
                try:
                    rollback_file(item)
                except (OSError, ValueError) as error:
                    print(f"  ⚠ could not undo Zed restore for {item.entry.destination}: {error}", file=sys.stderr)
            raise
        else:
            complete = True
        finally:
            errors = cleanup_restore(staged, directories.values(), complete)
            for error in errors:
                print(f"  ⚠ {error}", file=sys.stderr)
        for item in staged:
            print(f"  ✓ Zed {item.entry.destination.name} restored")
        if errors:
            raise RuntimeError("restored Zed files but could not finish cleanup")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    merge = modes.add_parser("preserve-local")
    merge.add_argument("--snapshot", required=True, type=Path)
    merge.add_argument("--live", type=Path)
    merge.add_argument("--output", type=Path, help="merged settings file; omit to validate only")
    restore = modes.add_parser("restore")
    restore.add_argument("--repo", required=True, type=Path)
    restore.add_argument("--settings-dir", required=True, type=Path)
    restore.add_argument("--preflight", action="store_true", help="check destinations without installing files")
    args = parser.parse_args()
    if args.mode == "restore":
        try:
            repo = args.repo.resolve(strict=True)
            plan = plan_restore(repo, args.settings_dir)
            if not args.preflight:
                install_restore(plan, repo)
        except KeyboardInterrupt:
            raise SystemExit("Zed restore interrupted")
        except (OSError, ValueError, RuntimeError) as error:
            raise SystemExit(f"Zed restore stopped: {error}")
        return
    try:
        settings = preserve_local(args.snapshot, args.live)
    except (OSError, ValueError) as error:
        raise SystemExit(f"Zed settings cannot be merged: {error}")
    if args.output:
        args.output.write_bytes(settings.encode("utf-8"))
        args.output.chmod(0o600)


if __name__ == "__main__":
    main()
