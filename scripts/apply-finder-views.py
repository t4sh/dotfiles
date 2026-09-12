#!/usr/bin/env python3
"""Reset Finder defaults and saved layouts; preserve home and Applications layouts."""
import argparse
import copy
from contextlib import contextmanager
from datetime import datetime
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import time

SKIP_NAMES = {".git", ".hg", ".svn", "node_modules", ".venv", "venv", "__pycache__", ".cache", ".Trash", ".dotfiles-local", ".dotfiles-backup"}
PACKAGE_SUFFIXES = {".app", ".bundle", ".framework", ".photoslibrary", ".photolibrary", ".musiclibrary", ".sparsebundle", ".backupdb"}


def applications(path):
    return any(part.casefold() == "applications" for part in path.parts)


def list_settings(settings):
    result = copy.deepcopy(settings)
    sort = "dateModified"
    result["sortColumn"] = sort
    columns = result.setdefault("columns", {})
    if isinstance(columns, list):
        column = next((c for c in columns if c.get("identifier") == sort), None)
        if column is None:
            column = {"identifier": sort}
            columns.append(column)
    else:
        column = columns.setdefault(sort, {})
    column.update(visible=True, ascending=False)
    return result


def preferences(domain):
    return plistlib.loads(subprocess.check_output(["defaults", "export", domain, "-"]))


def restart_finder():
    result = subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "Finder"], capture_output=True, text=True, timeout=10)
    if result.returncode not in (0, 1):
        raise RuntimeError("Cannot inspect Finder before restarting it")
    pids = {int(value) for value in result.stdout.split()}
    if pids:
        # Discard cached views: graceful termination writes stale .DS_Store
        # records back over the reset we just applied.
        subprocess.run(["killall", "-KILL", "Finder"], check=True, capture_output=True, timeout=10)
        deadline = time.monotonic() + 10
        while pids:
            for pid in pids.copy():
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    pids.remove(pid)
            if pids and time.monotonic() >= deadline:
                raise RuntimeError("Finder is still exiting; open it manually when ready")
            if pids:
                time.sleep(0.1)
    # LaunchServices can briefly retain the dead process even after pgrep no
    # longer sees it. Retry only its process-not-found transition (-600).
    deadline = time.monotonic() + 10
    while True:
        opened = subprocess.run(["open", "-a", "Finder"], capture_output=True, text=True, timeout=10)
        if opened.returncode == 0:
            return
        if "-600" not in opened.stderr or time.monotonic() >= deadline:
            raise RuntimeError(f"Finder metadata was reset, but reopening failed: {opened.stderr.strip()}")
        time.sleep(0.1)



def special_folders():
    return [p for p in (Path.home(), Path('/Applications'), Path('/System/Applications'),
                        Path.home() / 'Applications') if p.is_dir()]


APPLE_EVENT_TIMEOUT = 20
# Must exceed AppleScript's with-timeout so Finder's own error can surface.
OSASCRIPT_TIMEOUT = APPLE_EVENT_TIMEOUT + 5


def apply_special_folder_views(check=False):
    """Ask Finder to save its own folder settings; no .DS_Store rewriting."""
    script = f'''on run argv
    set checkOnly to false
    set folderPaths to argv
    if (count of argv) > 0 then
        if (item 1 of argv as text) is "check" then
            set checkOnly to true
            set folderPaths to rest of argv
        end if
    end if
    with timeout of {APPLE_EVENT_TIMEOUT} seconds
        tell application "Finder"
            repeat with folderPath in folderPaths
                set targetFolder to (POSIX file (contents of folderPath)) as alias
                set targetWindow to container window of targetFolder
                if checkOnly is false then
                    set current view of targetWindow to list view
                    tell list view options of targetWindow
                        set sort column to name column
                        set sort direction of column name column to normal
                    end tell
                end if
                if current view of targetWindow is not list view then error "Finder did not apply List view"
                if name of sort column of list view options of targetWindow is not name column then error "Finder did not apply Name sorting"
                if sort direction of column name column of list view options of targetWindow is not normal then error "Finder did not apply ascending order"
            end repeat
        end tell
    end timeout
end run
'''
    # LaunchServices readiness does not imply Finder can access folder windows.
    # Retry the idempotent operation itself only on transient native failures.
    deadline = time.monotonic() + 30
    command = ["osascript", "-"]
    if check:
        command.append("check")
    command.extend(map(str, special_folders()))
    while True:
        try:
            result = subprocess.run(
                command,
                input=script, text=True, capture_output=True, timeout=OSASCRIPT_TIMEOUT,
            )
            if result.returncode == 0:
                return
            detail = result.stderr.strip()
            transient = any(f'({code})' in detail for code in (-15260, -600, -609, -1712))
        except subprocess.TimeoutExpired:
            detail, transient = 'Finder request timed out', True
        if not transient or time.monotonic() >= deadline:
            raise RuntimeError(f"Home/Applications view reset failed: {detail}")
        time.sleep(0.2)


def preference_changes(finder, global_prefs):
    changes = {"com.apple.finder": {}, "NSGlobalDomain": {}}
    f = changes["com.apple.finder"]
    f.update(FXPreferredViewStyle="clmv", FXPreferredGroupBy="Date Modified", ShowPreviewPane=True, AppleShowAllFiles=True, _FXEnableColumnAutoSizing=True, FK_ArrangeBy="Date Modified")
    # Sorting within Finder groups is independent of the grouping field.
    f["FXArrangeGroupViewBy"] = "Name"
    for key in ("StandardViewOptions", "FK_StandardViewOptions2"):
        value = copy.deepcopy(finder.get(key, {}))
        value.setdefault("ColumnViewOptions", {}).update(ArrangeBy="modd", ShowPreview=True, FontSize=13, ColumnShowIcons=True, ShowIconThumbnails=True, PreviewDisclosureState=True)
        f[key] = value
    for key in ("StandardViewSettings", "FK_StandardViewSettings"):
        value = copy.deepcopy(finder.get(key, {}))
        for subkey in ("ListViewSettings", "ExtendedListViewSettingsV2"):
            value[subkey] = list_settings(value.get(subkey, {}))
        f[key] = value
    for key in {"FK_DefaultListViewSettings", "FK_iCloudListViewSettingsV2"} | {k for k in finder if k.startswith("FK_") and "ListViewSettings" in k}:
        f[key] = list_settings(finder.get(key, {}))
    g = changes["NSGlobalDomain"]
    for mode in ("Open", "Save"):
        g[f"NSNavPanelFileListModeFor{mode}Mode2"] = 3
        g[f"NSNavPanelFileLastListModeFor{mode}ModeKey"] = 3
    g.update(NSNavPanelExpandedStateForSaveMode=True, NSNavPanelExpandedStateForSaveMode2=True)
    return {domain: {k: v for k, v in values.items() if original.get(k) != v}
            for (domain, values), original in zip(changes.items(), (finder, global_prefs))}



@contextmanager
def io_deadline(description):
    """Bound synchronous provider I/O on the script's main thread."""
    def expired(signum, frame):
        raise TimeoutError(f"{description} exceeded 30 seconds")

    previous = signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, 30)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


@contextmanager
def paused_finder():
    """Always attempt recovery after a partial pause or catchable interruption."""
    def interrupted(signum, frame):
        raise SystemExit(128 + signum)

    previous = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGTERM, signal.SIGHUP)}
    try:
        stopped = subprocess.run(["killall", "-STOP", "Finder"], capture_output=True, timeout=10)
        if stopped.returncode not in (0, 1):
            raise RuntimeError("Could not pause Finder; no metadata was removed")
        with io_deadline("Finder metadata reset"):
            yield
    finally:
        # A second Ctrl-C/termination must not interrupt recovery itself.
        interrupt = signal.signal(signal.SIGINT, signal.SIG_IGN)
        for sig in previous:
            signal.signal(sig, signal.SIG_IGN)
        try:
            try:
                restart_finder()
            except BaseException:
                # If inspection/kill/relaunch failed, at least resume any
                # surviving Finder process instead of leaving it stopped.
                subprocess.run(["killall", "-CONT", "Finder"], capture_output=True, timeout=10)
                raise
        finally:
            signal.signal(signal.SIGINT, interrupt)
            for sig, handler in previous.items():
                signal.signal(sig, handler)


def directory_entries(folder):
    """Bound provider enumeration/stat calls; a stalled folder is reported."""
    with io_deadline("Directory read"):
        with os.scandir(folder) as children:
            return [(child.name, child.is_dir(follow_symlinks=False),
                     child.name == ".DS_Store" and child.is_file(follow_symlinks=False))
                    for child in children
                    if child.name not in SKIP_NAMES]


def daily_roots(errors):
    """Discover local FileVault organization and linked directories, not target trees."""
    vault = Path.home() / "FileVault"
    try:
        with io_deadline(f"FileVault discovery: {vault}"):
            if not vault.exists():
                return []
    except OSError as error:
        errors.append(f"{vault}: {error}")
        return []
    roots = set()

    def visit(folder):
        try:
            with io_deadline(f"Target discovery: {folder}"):
                if folder.is_symlink():
                    target = folder.resolve(strict=True)
                    if target.is_dir() and not applications(target):
                        roots.add(target)
                    return
            if applications(folder) or folder.name in SKIP_NAMES or folder.suffix.lower() in PACKAGE_SUFFIXES:
                return
            roots.add(folder)
            for name, is_directory, _ in directory_entries(folder):
                child = folder / name
                with io_deadline(f"Target discovery: {child}"):
                    is_link = child.is_symlink()
                if is_link or is_directory:
                    visit(child)
        except (OSError, RuntimeError) as error:
            errors.append(f"{folder}: {error}")

    visit(vault)
    return sorted(roots)


def find_stores(roots, errors, depth=1):
    """Inspect root and up to depth child levels, without following symlinks."""
    stores = set()
    home = Path.home().resolve()
    visited = 0
    last_progress = time.monotonic()

    def visit(folder, level):
        nonlocal visited, last_progress
        visited += 1
        if time.monotonic() - last_progress >= 5:
            print(f"  Scanned {visited} folders; {len(stores)} metadata files found. Current: {folder}", flush=True)
            last_progress = time.monotonic()
        if folder.is_symlink() or applications(folder) or folder.suffix.lower() in PACKAGE_SUFFIXES:
            return
        try:
            # Enumerate first: probing a nonexistent .DS_Store in a File Provider
            # root can block while the provider tries to resolve that name.
            for name, is_directory, is_metadata in directory_entries(folder):
                if name == ".DS_Store":
                    if folder != home and is_metadata:
                        stores.add(folder / name)
                    continue
                if level >= depth:
                    continue
                if name in SKIP_NAMES or Path(name).suffix.lower() in PACKAGE_SUFFIXES:
                    continue
                if folder == home / "Library" and name not in {"CloudStorage", "Mobile Documents"}:
                    continue
                child_path = folder / name
                if child_path in roots and child_path != root:
                    continue
                if is_directory:
                    visit(child_path, level + 1)
        except OSError as error:
            errors.append(f"{folder}: {error}")
            print(f"Skipped: {folder}: {error}", file=sys.stderr, flush=True)

    for root in roots:
        print(f"Scanning (depth {depth}): {root}", flush=True)
        visit(root, 0)
    return sorted(stores)


def check_store(path):
    if path.is_symlink() or path.parent.resolve() == Path.home().resolve() or applications(path.parent.resolve()):
        raise ValueError(f"Protected metadata: {path}")


def backup_store(path, backup):
    # Slow reads and backups happen while Finder is still responsive.
    with io_deadline(f"Metadata backup: {path}"):
        check_store(path)
        before = path.read_bytes()
        saved = backup / "folders" / str(path).lstrip("/")
        saved.parent.mkdir(parents=True, exist_ok=True)
        saved.write_bytes(before)
    return before


def reset_store(path, before):
    check_store(path)
    if path.read_bytes() != before:
        raise RuntimeError(f"Metadata changed during reset: {path}")
    path.unlink()


def write_preferences(changes):
    for domain, values in changes.items():
        for key, value in values.items():
            if isinstance(value, dict):
                payload = [plistlib.dumps(value).decode()]
            elif isinstance(value, bool):
                payload = ["-bool", str(value).lower()]
            elif isinstance(value, int):
                payload = ["-int", str(value)]
            else:
                payload = ["-string", value]
            subprocess.run(["defaults", "write", domain, key, *payload], check=True, timeout=10)


def check_policy():
    changes = preference_changes(preferences('com.apple.finder'), preferences('NSGlobalDomain'))
    for domain, values in changes.items():
        for key in values:
            print(f'Policy differs: {domain} {key}')
    return int(any(changes.values()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="list metadata without writing or restarting Finder")
    parser.add_argument("--root", type=Path, action="append", help="scan this directory instead of FileVault and its linked directories (repeatable)")
    parser.add_argument("--depth", type=int, default=1, help="child directory levels below each root (default: 1)")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--policy-only', action='store_true', help='apply preferences and folder exceptions without scanning or deleting metadata')
    modes.add_argument('--check', action='store_true', help='read back managed global preferences without mutations')
    modes.add_argument('--check-folders', action='store_true', help='verify List/Name exceptions through Finder; requires a GUI session')
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("macOS required")
    if args.depth < 0:
        parser.error("depth must be nonnegative")
    if (args.policy_only or args.check or args.check_folders) and (args.root or args.depth != 1):
        parser.error('scan options cannot be combined with policy/check modes')
    if args.check:
        return check_policy()
    if args.check_folders:
        apply_special_folder_views(check=True)
        print('Home/Applications List and Name sorting verified (grouping is not checked).')
        return 0
    if args.policy_only and args.dry_run:
        print('Would apply Finder/Open–Save preferences and Home/Applications List/Name exceptions; no metadata scrub.')
        return 0
    errors = []
    roots = [] if args.policy_only else [p.expanduser().absolute() for p in (args.root if args.root else daily_roots(errors))]
    validated = []
    for root in roots:
        try:
            with io_deadline(f"Root validation: {root}"):
                if root.is_symlink() or not root.is_dir():
                    parser.error("each root must be an existing directory, not a symlink")
                validated.append(root.resolve())
        except (OSError, RuntimeError) as error:
            errors.append(f"{root}: {error}")
    roots = list(dict.fromkeys(validated))
    stores = [] if args.policy_only else find_stores(roots, errors, args.depth)
    if args.dry_run:
        for path in stores:
            print(path)
        folders = ', '.join(map(str, special_folders())) or 'Home/Applications'
        print(f"Would reset {len(stores)} metadata files, then set {folders} to alphabetical List view.")
        for error in errors:
            print(f"Skipped: {error}", file=sys.stderr)
        return int(bool(errors))
    finder, globals_ = preferences("com.apple.finder"), preferences("NSGlobalDomain")
    changes = preference_changes(finder, globals_)
    backup = None
    prepared = []
    if stores:
        os.umask(0o077)
        backup = Path.home() / ".dotfiles-local/finder-views" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup.mkdir(parents=True)
        for domain, original in (("com.apple.finder", finder), ("NSGlobalDomain", globals_)):
            (backup / f"{domain}.plist").write_bytes(plistlib.dumps(original))
        # Preserve the exceptions' original metadata too, before Finder changes it.
        for folder in special_folders():
            metadata = folder / ".DS_Store"
            if metadata.is_file() and not metadata.is_symlink():
                saved = backup / "folders" / str(metadata).lstrip("/")
                saved.parent.mkdir(parents=True, exist_ok=True)
                saved.write_bytes(metadata.read_bytes())
        for path in stores:
            try:
                prepared.append((path, backup_store(path, backup)))
            except (OSError, ValueError, RuntimeError) as error:
                errors.append(str(error))
    write_preferences(changes)
    changed = 0
    if prepared:
        # Only revalidation and deletion require Finder to be paused. A single
        # deadline bounds the entire pause, including cloud metadata operations.
        with paused_finder():
            for path, before in prepared:
                try:
                    reset_store(path, before)
                    changed += 1
                except TimeoutError:
                    raise  # Leave the pause immediately; do not continue untimed.
                except (OSError, ValueError, RuntimeError) as error:
                    errors.append(str(error))
    else:
        restart_finder()
    try:
        apply_special_folder_views()
        print("Home and existing Applications folders: List / Name ascending (verified through Finder; grouping is not checked).")
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        errors.append(str(error))
    print("Finder defaults: Columns / Date Modified groups / Name within groups / previews / text 13 / automatic column sizing.")
    print("Native Open/Save defaults: Columns / Date Modified. Reopen existing dialogs.")
    if backup is not None:
        (backup / "result.json").write_text(json.dumps({"roots": list(map(str, roots)), "depth": args.depth, "removed": changed, "errors": errors}, indent=2))
        print(f"Reset {changed}/{len(stores)} metadata files; home and Applications metadata was excluded from deletion.")
        print(f"Previous metadata and preferences: {backup}")
    for error in errors:
        print(f"Skipped: {error}", file=sys.stderr)
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
